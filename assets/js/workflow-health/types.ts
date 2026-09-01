/**
 * Every state a run can finish in other than success. Mirrors the failure half
 * of `Lightning.Run.final_states/0`; runs still in flight never reach the
 * client, since they have no outcome yet.
 *
 * This list is the single definition both donuts derive from: Outcomes sums it
 * for its Failed wedge and the failure breakdown keys its palette by it, so a
 * state added here cannot be counted by one panel and dropped by the other.
 */
export const FAILURE_STATES = [
  'failed',
  'crashed',
  'cancelled',
  'killed',
  'exception',
  'lost',
] as const;

export type FailureState = (typeof FAILURE_STATES)[number];

export type RunStateCounts = Record<'success' | FailureState, number>;

/**
 * The `outcomes` response from `LightningWeb.API.WorkflowHealthController`.
 * Counts only; `Lightning.Workflows.Stats` does the bucketing.
 *
 * One response feeds both donuts: Outcomes folds the failure states together
 * and the failure breakdown slices them apart, and it is the same aggregate
 * either way — a second request would re-run the identical query.
 */
export interface Outcomes {
  window: { from: string; to: string };
  counts: RunStateCounts;
}

/**
 * One row of the triage table: the parts of an error signature (CON-31) and
 * the number of runs that carry it. `step_name` and `adaptor` are null for a
 * run that failed before reaching a step; `error_type` is null when nothing
 * reported one.
 */
export interface FailureSignature {
  count: number;
  exit_reason: string;
  error_type: string | null;
  step_name: string | null;
  adaptor: string | null;
}

/** The `failures` response, heaviest signature first. */
export interface FailureSignatures {
  window: { from: string; to: string };
  signatures: FailureSignature[];
}
