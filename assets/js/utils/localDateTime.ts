/**
 * Helpers for `datetime-local` inputs.
 *
 * A `datetime-local` input speaks wall-clock time in the browser's timezone,
 * but the server stores and filters timestamps in UTC. Without a conversion the
 * wall-clock string is read as UTC, so a filter set to "16:40" by a user in
 * UTC+1 is applied as 16:40 UTC - an hour later than the times the same page
 * displays. See https://github.com/OpenFn/lightning/issues/4983.
 */

/**
 * Converts the value of a `datetime-local` input - a wall-clock time in the
 * browser's timezone - into a UTC ISO 8601 string.
 *
 * Returns null when the value is empty or can't be parsed.
 */
export function localInputToUTC(
  value: string | null | undefined
): string | null {
  if (!value) return null;

  // Date-time strings without an offset are parsed as local time.
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;

  return date.toISOString();
}

/**
 * Converts a UTC timestamp into the wall-clock string a `datetime-local` input
 * expects (`YYYY-MM-DDTHH:mm`), in the browser's timezone.
 *
 * Returns an empty string when the value is empty or can't be parsed, which is
 * what an empty `datetime-local` input holds.
 */
export function utcToLocalInput(value: string | null | undefined): string {
  if (!value) return '';

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';

  const pad = (n: number) => String(n).padStart(2, '0');

  return (
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
    `T${pad(date.getHours())}:${pad(date.getMinutes())}`
  );
}
