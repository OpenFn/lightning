/**
 * Every state a work order finishes in that counts as a failure. Mirrors
 * `Stats`'s `@failure_states`; work orders still in flight never reach the
 * client, since they have no outcome yet.
 *
 * `cancelled` is deliberately not here — it is a final state, but someone
 * stopped that work order on purpose, so it is not a failure to drive down. It
 * gets its own Outcomes slice instead.
 *
 * This list is the single definition both donuts derive from: Outcomes sums it
 * for its Failed wedge and the failure breakdown keys its palette by it, so a
 * state added here cannot be counted by one panel and dropped by the other.
 */
export const FAILURE_STATES = [
  'failed',
  'crashed',
  'killed',
  'exception',
  'lost',
  'rejected',
] as const;

export type FailureState = (typeof FAILURE_STATES)[number];

export type WorkOrderStateCounts = Record<
  'success' | 'cancelled' | FailureState,
  number
>;

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
  counts: WorkOrderStateCounts;
}

/**
 * One row of the triage table: the parts of an error signature (CON-31) and
 * the number of work orders that carry it. `step_name` and `adaptor` are null
 * for a work order whose run failed before reaching a step, or never ran at
 * all; `error_type` is null when nothing reported one.
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
