import { createServer } from 'http';
import { gunzipSync } from 'zlib';

export interface SentryItem {
  header: { type: string; [key: string]: unknown };
  payload: unknown;
}

// The Elixir SDK sends `exception` as a bare list, the browser SDK as
// `{ values: [...] }`; both are valid per the protocol.
export interface SentryEvent {
  platform?: string;
  environment?: string;
  release?: string;
  exception?: unknown;
  request?: { url?: string; env?: Record<string, unknown> };
  tags?: Record<string, string>;
  [key: string]: unknown;
}

export interface SentryEnvelope {
  header: Record<string, unknown>;
  items: SentryItem[];
}

// https://develop.sentry.dev/sdk/envelopes/
export function parseEnvelope(body: Buffer): SentryEnvelope {
  let offset = 0;

  const readLine = () => {
    let end = body.indexOf(0x0a, offset);
    if (end === -1) end = body.length;
    const line = body.subarray(offset, end).toString('utf-8');
    offset = end + 1;
    return line;
  };

  const header = JSON.parse(readLine()) as SentryEnvelope['header'];
  const items: SentryItem[] = [];

  while (offset < body.length) {
    const line = readLine();
    if (!line.trim()) continue;
    const itemHeader = JSON.parse(line) as SentryItem['header'] & {
      length?: number;
    };

    let raw: string;
    if (typeof itemHeader.length === 'number') {
      raw = body.subarray(offset, offset + itemHeader.length).toString('utf-8');
      offset += itemHeader.length + 1;
    } else {
      raw = readLine();
    }

    let payload: unknown = raw;
    try {
      payload = JSON.parse(raw);
    } catch {
      // Attachments and other non-JSON items stay as strings.
    }
    items.push({ header: itemHeader, payload });
  }

  return { header, items };
}

/**
 * Records every Sentry envelope posted to it. Point a DSN at
 * `http://publickey@localhost:<port>/1` and the SDKs post to
 * `/api/1/envelope/`.
 */
export async function startSentryListener(port: number) {
  const envelopes: SentryEnvelope[] = [];

  const server = createServer((req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Headers', '*');
    res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');

    if (req.method !== 'POST') {
      res.writeHead(204).end();
      return;
    }

    const chunks: Buffer[] = [];
    req.on('data', (chunk: Buffer) => chunks.push(chunk));
    req.on('end', () => {
      let body = Buffer.concat(chunks);
      if (req.headers['content-encoding'] === 'gzip') body = gunzipSync(body);
      try {
        envelopes.push(parseEnvelope(body));
      } catch (error) {
        console.error('[sentry-listener] unparseable envelope', error);
      }
      res.writeHead(200, { 'Content-Type': 'application/json' }).end('{}');
    });
  });

  await new Promise<void>(resolve => server.listen(port, resolve));

  return {
    envelopes,
    events: () =>
      envelopes.flatMap(e =>
        e.items
          .filter(item => item.header.type === 'event')
          .map(item => item.payload as SentryEvent)
      ),
    close: () => new Promise<void>(resolve => server.close(() => resolve())),
  };
}
