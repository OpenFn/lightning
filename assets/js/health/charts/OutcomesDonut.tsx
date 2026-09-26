import { stateUrl } from '../historyUrl';
import {
  FAILURE_STATES,
  failureTotal,
  type WorkOrderStateCounts,
} from '../types';

import { Donut } from './Donut';

/**
 * Finished work order outcomes as a donut, with the total in the middle.
 *
 * Every state in `FAILURE_STATES` is folded into one `failed` slice; the
 * failure breakdown panel is where they come apart. `cancelled` sits outside
 * both — it is a finished outcome but not a failure — so it is drawn here and
 * nowhere else, which is also what keeps this total equal to the page's own.
 * Pending is not a slice: work still in flight has no outcome yet.
 *
 * Every slice links to the work orders it counts, over the same window the
 * page is showing.
 */

// Status colors, not a categorical palette — these are states, and these steps
// are reserved so they never impersonate a series. Grey for cancelled is the
// convention the rest of the app already uses (`dashboard_components.ex` gives
// it `bg-gray-500`), and it reads as "stopped, not broken" beside the red.
//
// Exported because the volume chart shares this row: a green bar and a green
// wedge on one screen have to mean the same thing.
export const SUCCESS = '#0ca30c';
export const FAILED = '#d03b3b';
export const CANCELLED = 'var(--color-gray-500)';

interface OutcomesDonutProps {
  counts: WorkOrderStateCounts;
  emptyMessage: string;
  projectId: string;
  workflowId: string;
  /** `window.from` off the same response — the picked range's start. */
  from: string;
}

export const OutcomesDonut = ({
  counts,
  emptyMessage,
  projectId,
  workflowId,
  from,
}: OutcomesDonutProps) => (
  <Donut
    slices={[
      {
        key: 'success',
        label: 'Success',
        color: SUCCESS,
        value: counts.success,
        href: stateUrl(projectId, workflowId, from, 'success'),
      },
      {
        key: 'failed',
        label: 'Failed',
        color: FAILED,
        value: failureTotal(counts),
        href: stateUrl(projectId, workflowId, from, ...FAILURE_STATES),
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
              href: stateUrl(projectId, workflowId, from, 'cancelled'),
            },
          ]
        : []),
    ]}
    emptyMessage={emptyMessage}
  />
);
