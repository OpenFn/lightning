/**
 * Green trigger-type pill shown on the show panel and the wizard's Choose step.
 * Kept tiny and presentational so every call site renders an identical badge.
 *
 * - webhook → globe icon + "Webhook"
 * - cron    → clock icon + "Schedule / Cron"
 * - kafka   → queue-list icon + "Kafka"
 */
export function TriggerTypeBadge({
  type = 'webhook',
}: {
  type?: 'webhook' | 'cron' | 'kafka';
}) {
  const { icon, label } =
    type === 'cron'
      ? { icon: 'hero-clock-mini', label: 'Schedule / Cron' }
      : type === 'kafka'
        ? { icon: 'hero-queue-list-mini', label: 'Kafka' }
        : { icon: 'hero-globe-alt-mini', label: 'Webhook' };

  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full border
        border-green-200 bg-green-50 px-2.5 py-1 text-xs font-medium
        text-green-700"
    >
      <span className={`${icon} h-4 w-4`} />
      {label}
    </span>
  );
}
