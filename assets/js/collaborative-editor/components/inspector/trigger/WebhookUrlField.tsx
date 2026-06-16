interface WebhookUrlFieldProps {
  /** The webhook ingest URL to display. */
  url: string;
  /** Copy feedback text ('' when idle, e.g. 'Copied!' after copying). */
  copyText: string;
  /** Copies the given text to the clipboard. */
  onCopy: (text: string) => void;
}

/**
 * Read-only "Webhook URL" field shared by the show panel and the Choose step.
 *
 * Renders the full ingest URL (wrapping, not truncated) with a POST method pill
 * and a copy-icon button, matching the trigger-flow design. Webhook endpoints
 * receive POST requests, so the method tag is POST.
 */
export function WebhookUrlField({
  url,
  copyText,
  onCopy,
}: WebhookUrlFieldProps) {
  const copied = Boolean(copyText);

  return (
    <div>
      <div className="block text-sm font-medium leading-6 text-slate-800">
        Webhook URL
      </div>
      <div
        className="relative mt-2 flex items-start gap-3 rounded-lg border
          border-gray-200 p-2"
      >
        <span
          className="shrink-0 rounded bg-emerald-50 px-2 py-1 font-mono
            text-[10px] font-medium leading-none text-emerald-700"
        >
          POST
        </span>
        <span className="min-w-0 break-all pr-7 font-mono text-xs leading-5 text-slate-600">
          {url}
        </span>
        <button
          type="button"
          onClick={() => onCopy(url)}
          title={copyText || 'Copy URL'}
          aria-label={copyText || 'Copy URL'}
          className="absolute right-2 top-2 rounded border border-gray-200
            bg-white p-1 text-gray-400 hover:bg-gray-50 hover:text-gray-600"
        >
          <span
            className={`block h-3 w-3 ${
              copied
                ? 'hero-check-micro text-green-600'
                : 'hero-square-2-stack-micro'
            }`}
          />
        </button>
      </div>
      <p className="mt-2 text-xs text-slate-500">
        Copy this URL into your source application, when we receive a request.
        You'll see it here.
      </p>
    </div>
  );
}
