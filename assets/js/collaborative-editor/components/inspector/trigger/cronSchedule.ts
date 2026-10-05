/**
 * Cron humanization helper for the cron trigger inspector.
 *
 * `humanizeCron` turns a stored cron expression into friendly text (via
 * `cronstrue`) for the read-only show panel. Authoring the schedule itself is
 * handled by the dropdown-based {@link CronFieldBuilder}, which does its own
 * cron parsing/serialization, so no natural-language parser lives here.
 */

import cronstrue from 'cronstrue';

/**
 * Humanize a cron expression for display. Returns `null` if cronstrue throws
 * (e.g. on a malformed expression).
 */
export function humanizeCron(expr: string): string | null {
  try {
    return cronstrue.toString(expr);
  } catch {
    return null;
  }
}
