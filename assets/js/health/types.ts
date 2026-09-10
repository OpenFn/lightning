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
 * How many work orders failed. Summed from `FAILURE_STATES` rather than taken
 * as `total - success`, so the outcomes donut's Failed wedge, the failure
 * breakdown's slices and the page's own caption are all driven by the same
 * list.
 */
export const failureTotal = (counts: WorkOrderStateCounts) =>
  FAILURE_STATES.reduce((sum, state) => sum + counts[state], 0);

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
 * One row of the triage table: the parts of an error signature and
 * the number of work orders that carry it. `step_name` and `adaptor` are null
 * for a work order whose run failed before reaching a step, or never ran at
 * all; `error_type` is null when nothing reported one. `job_id` is the same
 * story as `step_name`/`adaptor` — null for a run-level row and for a
 * rejected one — but it is the key the history filter matches on, since
 * matching on the resolved name would need a snapshot lookup the filter
 * doesn't do.
 */
export interface ErrorSignature {
  count: number;
  exit_reason: string;
  error_type: string | null;
  job_id: string | null;
  step_name: string | null;
  adaptor: string | null;
}

/** The `failures` response, heaviest signature first. */
export interface ErrorSignatures {
  window: { from: string; to: string };
  signatures: ErrorSignature[];
}
