import { CodeViewer } from './CodeViewer';

const MAX_STRING_LENGTH = 140;

function truncateStrings(value: unknown): unknown {
  if (typeof value === 'string') {
    return value.length > MAX_STRING_LENGTH
      ? value.slice(0, MAX_STRING_LENGTH) + '\u2026'
      : value;
  }
  if (Array.isArray(value)) {
    return value.map(truncateStrings);
  }
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([k, v]) => [k, truncateStrings(v)])
    );
  }
  return value;
}

function parseValues(data: unknown): unknown {
  if (Array.isArray(data)) {
    return data.map(parseValues);
  }
  if (data !== null && typeof data === 'object') {
    const obj = data as Record<string, unknown>;
    const entries = Object.entries(obj).map(([k, v]): [string, unknown] => {
      if (k === 'value' && typeof v === 'string') {
        try {
          return [k, parseValues(JSON.parse(v))];
        } catch {
          return [k, v];
        }
      }
      return [k, parseValues(v)];
    });

    // Put "key" first so the display reads naturally
    entries.sort((a, b) => (a[0] === 'key' ? -1 : b[0] === 'key' ? 1 : 0));

    return Object.fromEntries(entries);
  }
  return data;
}

export const CollectionPreviewViewer = ({ json }: { json: string }) => {
  // `displayContent` has strings truncated for readability; `json` is
  // passed to the copy button so the user always copies the full original
  // content.
  let displayContent = json;
  try {
    const parsed = parseValues(JSON.parse(json));
    displayContent = JSON.stringify(truncateStrings(parsed), null, 2);
  } catch {
    // use as-is if not valid JSON
  }

  return <CodeViewer content={displayContent} copyContent={json} />;
};
