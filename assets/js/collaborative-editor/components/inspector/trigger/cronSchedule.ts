/**
 * Cron humanization helper for the cron trigger inspector and diagram node.
 *
 * `humanizeCron` turns a stored cron expression into friendly text (via
 * `cronstrue`) for the show panel, the builder preview and the diagram node.
 * Authoring the schedule itself is handled by the dropdown-based
 * {@link CronFieldBuilder}, which does its own cron parsing/serialization, so
 * no natural-language parser lives here.
 */

import cronstrue from 'cronstrue';

const LAST_CLOCK_TIME = /(\d{2}:\d{2} [AP]M)(?!.*\d{2}:\d{2} [AP]M)/;

/**
 * Humanize a cron expression for display. Returns `null` if cronstrue throws
 * (e.g. on a malformed expression).
 *
 * Cron schedules run in UTC, so "UTC" follows the last clock time in the text
 * ("At 09:00 AM UTC, Monday through Friday"). It sits next to the time, not at
 * the end, so a clamped label (the diagram node) cuts the days, not the zone.
 */
export function humanizeCron(expr: string): string | null {
  try {
    return cronstrue.toString(expr).replace(LAST_CLOCK_TIME, '$1 UTC');
  } catch {
    return null;
  }
}
