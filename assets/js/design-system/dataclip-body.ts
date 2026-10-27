import type { DataclipBody } from '@openfn/ui';

/**
 * The body of a dataclip, fetched in the browser as the old `DataclipViewer`
 * island did: a body can be megabytes, so it never travels in props, and the
 * controller keeps its own authorisation and caching. Pretty-printed when it
 * is JSON; the viewer's own words, as an error and not as text, when it is
 * not there.
 */
export const fetchDataclipBody = async (
  id: string,
  signal: AbortSignal
): Promise<DataclipBody> => {
  try {
    const response = await fetch(`/dataclip/body/${id}`, { signal });
    if (response.status === 404) return { error: 'Dataclip not found' };
    if (!response.ok) return { error: 'Failed to load content' };
    const text = await response.text();
    try {
      return { text: JSON.stringify(JSON.parse(text), null, 2) };
    } catch {
      return { text };
    }
  } catch {
    return { error: 'Failed to load content' };
  }
};
