import type { Outcomes } from './types';

/**
 * The line under a health page's title: the window it covers and how many work
 * orders finished in it.
 *
 * Shared by both health pages, so the project total and a workflow's total are
 * always phrased and pluralised the same way.
 */
export const Subtitle = ({ outcomes }: { outcomes: Outcomes | null }) => {
  if (!outcomes) return null;

  const days = windowDays(outcomes.window);
  const total = workOrderTotal(outcomes.counts);

  return (
    <p className="text-sm text-gray-500">
      Last {days} day{days === 1 ? '' : 's'} · {total.toLocaleString()} work
      order{total === 1 ? '' : 's'}
    </p>
  );
};

export const workOrderTotal = (counts: Outcomes['counts']) =>
  Object.values(counts).reduce((sum, count) => sum + count, 0);

/**
 * Derived from the window rather than hard-coded, so the pages keep telling the
 * truth when the range stops being a fixed 30 days.
 */
export const windowDays = ({ from, to }: { from: string; to: string }) =>
  Math.round((Date.parse(to) - Date.parse(from)) / 86_400_000);
