import { Badge } from '#/ui/Badge';

/**
 * Green trigger-type pill shown on the show panel and the wizard's Choose step.
 * Kept tiny and presentational so every call site renders an identical badge.
 *
 * - webhook → globe icon + "Webhook"
 * - cron    → clock icon + "Schedule / Cron"
 */
export function TriggerTypeBadge({
  type = 'webhook',
}: {
  type?: 'webhook' | 'cron';
}) {
  const { icon, label } =
    type === 'cron'
      ? { icon: 'hero-clock-mini', label: 'Schedule / Cron' }
      : { icon: 'hero-globe-alt-mini', label: 'Webhook' };

  return (
    <Badge color="success" icon={icon}>
      {label}
    </Badge>
  );
}
