import { FAILURE_STATES, type WorkOrderStateCounts } from '../types';

import { Donut } from './Donut';

/**
 * Finished work order outcomes as a donut, with the total in the middle.
 *
 * Every state in `FAILURE_STATES` is folded into one `failed` slice; the
 * failure breakdown panel is where they come apart. `cancelled` sits outside
 * both — it is a finished outcome but not a failure — so it is drawn here and
 * nowhere else, which is also what keeps this total equal to the page's own.
 * Pending is not a slice: work still in flight has no outcome yet.
 */

// Status colors, not a categorical palette — these are states, and these steps
// are reserved so they never impersonate a series. Grey for cancelled is the
// convention the rest of the app already uses (`dashboard_components.ex` gives
// it `bg-gray-500`), and it reads as "stopped, not broken" beside the red.
const SUCCESS = '#0ca30c';
const FAILED = '#d03b3b';
const CANCELLED = '#6b7280';

interface OutcomesDonutProps {
  counts: WorkOrderStateCounts;
  emptyMessage: string;
}

export const OutcomesDonut = ({ counts, emptyMessage }: OutcomesDonutProps) => (
  <Donut
    slices={[
      {
        key: 'success',
        label: 'Success',
        color: SUCCESS,
        value: counts.success,
      },
      {
        key: 'failed',
        label: 'Failed',
        color: FAILED,
        value: failureTotal(counts),
      },
      // Only drawn when it happened. Success and Failed are this panel's
      // headline pair and stay put at zero — "Failed 0" is the answer someone
      // came for — but a "Cancelled 0" row on every healthy workflow is noise.
      ...(counts.cancelled > 0
        ? [
            {
              key: 'cancelled',
              label: 'Cancelled',
              color: CANCELLED,
              value: counts.cancelled,
            },
          ]
        : []),
    ]}
    emptyMessage={emptyMessage}
  />
);

// Summed from `FAILURE_STATES` rather than taken as `total - success`, so this
// wedge and the failure breakdown's slices are driven by the same list.
const failureTotal = (counts: WorkOrderStateCounts) =>
  FAILURE_STATES.reduce((sum, state) => sum + counts[state], 0);
