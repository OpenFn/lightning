/**
 * Tests for the adaptor catalogue HTTP client
 */

import { afterEach, describe, expect, test, vi } from 'vitest';

import { getAdaptorCatalogue } from '../../../js/collaborative-editor/api/adaptors';

describe('getAdaptorCatalogue', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  test('fetches the catalogue from the same-origin route with credentials', async () => {
    const mockData = [{ name: '@openfn/language-http' }];
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ data: mockData }),
    });
    vi.stubGlobal('fetch', fetchMock);

    const result = await getAdaptorCatalogue();

    expect(fetchMock).toHaveBeenCalledWith('/adaptors/catalogue', {
      credentials: 'same-origin',
    });
    expect(result).toEqual({ data: mockData });
  });

  test('throws when the response is not ok', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: false,
        statusText: 'Internal Server Error',
      })
    );

    await expect(getAdaptorCatalogue()).rejects.toThrow(
      'Internal Server Error'
    );
  });
});
