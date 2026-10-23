/**
 * The body of a dataclip, fetched in the browser as the old `DataclipViewer`
 * island did: a body can be megabytes, so it never travels in props, and the
 * controller keeps its own authorisation and caching. Pretty-printed when it
 * is JSON; the viewer's own words when it is not there.
 */
export const fetchDataclipBody = async (id: string, signal: AbortSignal) => {
  try {
    const response = await fetch(`/dataclip/body/${id}`, { signal });
    if (response.status === 404) return 'Dataclip not found';
    if (!response.ok) return 'Failed to load content';
    const text = await response.text();
    try {
      return JSON.stringify(JSON.parse(text), null, 2);
    } catch {
      return text;
    }
  } catch {
    return 'Failed to load content';
  }
};
