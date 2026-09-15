import { stateUrls } from '../historyUrl';
import {
  FAILURE_STATES,
  type FailureState,
  type WorkOrderStateCounts,
} from '../types';

import { Donut } from './Donut';
import { FAILED } from './OutcomesDonut';

/**
 * Failed work orders split by the state they finished in, as a donut.
 *
 * `success` is not a slice — this panel breaks down the Outcomes donut's red
 * wedge, so its shares are of failures and the two totals have to agree. Both
 * panels read the same `FAILURE_STATES` list, so they cannot drift apart.
 *
 * Every slice links to the work orders it counts, over the same window the
 * page is showing.
 */

// Categorical, not status: every slice here is already a failure, so hue
// carries identity rather than severity. `failed` keeps the status red the
// Outcomes donut gives it, since the panels sit side by side and that slice is
// the same work orders. The remaining five are categorical slots, validated
// all-pairs (worst CVD ΔE 6.1) — which is only legal alongside `Donut`'s
// always-on legend, so don't drop it. `rejected` took the slot `cancelled`
// vacated when it stopped counting as a failure, so this is still the same
// validated six.
//
// A `Record` keyed by `FailureState`, so adding a state without choosing a
// colour for it is a compile error rather than a silently missing slice.
const COLORS: Record<FailureState, string> = {
  failed: FAILED,
  crashed: '#e87ba4',
  killed: '#4a3aa7',
  exception: '#2a78d6',
  lost: '#1baf7a',
  rejected: '#eda100',
};

interface FailureBreakdownDonutProps {
  counts: WorkOrderStateCounts;
  emptyMessage: string;
  projectId: string;
  workflowId: string;
  /** `window.from` off the same response — the picked range's start. */
  from: string;
}

export const FailureBreakdownDonut = ({
  counts,
  emptyMessage,
  projectId,
  workflowId,
  from,
}: FailureBreakdownDonutProps) => {
  const url = stateUrls(projectId, workflowId, from);

  return (
    <Donut
      // States that never happened are dropped rather than drawn at zero — six
      // rows of which four read "0" buries the two that matter.
      slices={FAILURE_STATES.filter(state => counts[state] > 0).map(state => ({
        key: state,
        label: state,
        color: COLORS[state],
        value: counts[state],
        href: url(state),
      }))}
      emptyMessage={emptyMessage}
    />
  );
};
