import type { RunStateCounts } from '../types';

import { Donut } from './Donut';

/**
 * Finished run outcomes as a donut, with the total in the middle.
 *
 * The six failure states are folded into one `failed` slice; the failure
 * breakdown panel is where they come apart. Pending is not a slice: work still
 * in flight has no outcome yet.
 */

// Status colors, not a categorical palette — these are states, and these steps
// are reserved so they never impersonate a series.
const SUCCESS = '#0ca30c';
const FAILED = '#d03b3b';

interface OutcomesDonutProps {
  counts: RunStateCounts;
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
    ]}
    emptyMessage={emptyMessage}
  />
);

const failureTotal = (counts: RunStateCounts) =>
  Object.values(counts).reduce((sum, count) => sum + count, 0) - counts.success;
