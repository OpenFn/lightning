/**
 * Green "Webhook" pill (globe icon) shown on the webhook show panel and the
 * wizard's Choose step. Kept tiny and presentational so both call sites render
 * an identical badge.
 */
export function TriggerTypeBadge() {
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full border
        border-green-200 bg-green-50 px-2.5 py-1 text-xs font-medium
        text-green-700"
    >
      <span className="hero-globe-alt-mini h-4 w-4" />
      Webhook
    </span>
  );
}
