import { afterEach, describe, expect, test, vi } from 'vitest';

import { fetchDataclipBody } from '../../js/design-system/dataclip-body';

const ID = '9a8b7c6d-3333-4a4a-8b8b-0123456789ab';

const load = (answer: () => Promise<Response>) => {
  vi.stubGlobal('fetch', vi.fn(answer));
  return fetchDataclipBody(ID, new AbortController().signal);
};

describe('fetchDataclipBody', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  test('pretty-prints a JSON body as text', async () => {
    const body = await load(() => Promise.resolve(new Response('{"x":1}')));
    expect(body).toEqual({ text: '{\n  "x": 1\n}' });
  });

  test('returns a body that is not JSON as it came', async () => {
    const body = await load(() => Promise.resolve(new Response('plain text')));
    expect(body).toEqual({ text: 'plain text' });
  });

  test('says a missing dataclip is not found, as an error and not as text', async () => {
    const body = await load(() =>
      Promise.resolve(new Response('', { status: 404 }))
    );
    expect(body).toEqual({ error: 'Dataclip not found' });
  });

  test('says any other refusal failed to load', async () => {
    const body = await load(() =>
      Promise.resolve(new Response('', { status: 500 }))
    );
    expect(body).toEqual({ error: 'Failed to load content' });
  });

  test('says a network failure failed to load', async () => {
    const body = await load(() => Promise.reject(new TypeError('offline')));
    expect(body).toEqual({ error: 'Failed to load content' });
  });
});
