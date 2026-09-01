import type { RunStateCounts } from '../types';

import { Donut } from './Donut';

/**
 * Failed runs split by the state they finished in, as a donut.
 *
 * `success` is not a slice — this panel breaks down the Outcomes donut's red
 * wedge, so its shares are of failures and the two totals have to agree.
 */

// Categorical, not status: every slice here is already a failure, so hue
// carries identity rather than severity. `failed` keeps the status red the
// Outcomes donut gives it, since the panels sit side by side and that slice is
// the same runs. The remaining five are categorical slots, validated all-pairs
// (worst CVD ΔE 6.1) — which is only legal alongside `Donut`'s always-on
// legend, so don't drop it.
const SLICES = [
  { key: 'failed', color: '#d03b3b' },
  { key: 'crashed', color: '#e87ba4' },
  { key: 'cancelled', color: '#eda100' },
  { key: 'killed', color: '#4a3aa7' },
  { key: 'exception', color: '#2a78d6' },
  { key: 'lost', color: '#1baf7a' },
] as const satisfies readonly { key: keyof RunStateCounts; color: string }[];

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
    slices={SLICES.filter(({ key }) => counts[key] > 0).map(
      ({ key, color }) => ({ key, label: key, color, value: counts[key] })
    )}
    emptyMessage={emptyMessage}
  />
);
