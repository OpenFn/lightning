import { JsonViewer } from './JsonViewer';

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

export const CollectionPreviewViewer = ({ json }: { json: string }) => {
  // `displayContent` has strings truncated for readability; `json` is
  // passed to the copy button so the user always copies the full original
  // content.
  let displayContent = json;
  try {
    const parsed = JSON.parse(json);
    displayContent = JSON.stringify(truncateStrings(parsed), null, 2);
  } catch {
    // use as-is if not valid JSON
  }

  return <JsonViewer content={displayContent} copyContent={json} />;
};
