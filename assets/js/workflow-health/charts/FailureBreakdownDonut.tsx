import {
  FAILURE_STATES,
  type FailureState,
  type RunStateCounts,
} from '../types';

import { Donut } from './Donut';

/**
 * Failed runs split by the state they finished in, as a donut.
 *
 * `success` is not a slice — this panel breaks down the Outcomes donut's red
 * wedge, so its shares are of failures and the two totals have to agree. Both
 * panels read the same `FAILURE_STATES` list, so they cannot drift apart.
 */

// Categorical, not status: every slice here is already a failure, so hue
// carries identity rather than severity. `failed` keeps the status red the
// Outcomes donut gives it, since the panels sit side by side and that slice is
// the same runs. The remaining five are categorical slots, validated all-pairs
// (worst CVD ΔE 6.1) — which is only legal alongside `Donut`'s always-on
// legend, so don't drop it.
//
// A `Record` keyed by `FailureState`, so adding a state without choosing a
// colour for it is a compile error rather than a silently missing slice.
const COLORS: Record<FailureState, string> = {
  failed: '#d03b3b',
  crashed: '#e87ba4',
  cancelled: '#eda100',
  killed: '#4a3aa7',
  exception: '#2a78d6',
  lost: '#1baf7a',
};

interface FailureBreakdownDonutProps {
  counts: RunStateCounts;
  emptyMessage: string;
}

export const FailureBreakdownDonut = ({
  counts,
  emptyMessage,
}: FailureBreakdownDonutProps) => (
  <Donut
    // States that never happened are dropped rather than drawn at zero — six
    // rows of which four read "0" buries the two that matter.
    slices={FAILURE_STATES.filter(state => counts[state] > 0).map(state => ({
      key: state,
      label: state,
      color: COLORS[state],
      value: counts[state],
    }))}
    emptyMessage={emptyMessage}
  />
);
