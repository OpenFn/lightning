import { useEffect, useState } from 'react';

/**
 * Every state a run can finish in. Mirrors `Lightning.Run.final_states/0`;
 * runs still in flight never reach the client, since they have no outcome yet.
 */
export type RunStateCounts = Record<
  | 'success'
  | 'failed'
  | 'crashed'
  | 'cancelled'
  | 'killed'
  | 'exception'
  | 'lost',
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

interface HealthState {
  outcomes: Outcomes | null;
  outcomesError: string | null;
  signatures: FailureSignatures | null;
  signaturesError: string | null;
}

const getJSON = async <T>(url: string, signal: AbortSignal): Promise<T> => {
  const response = await fetch(url, { credentials: 'same-origin', signal });

  if (!response.ok) throw new Error('Could not load workflow stats');

  return response.json() as Promise<T>;
};

/**
 * Fetches each chart's slice of the health stats once.
 *
 * Kept apart from the components so charts stay pure functions of their props —
 * a chart can be rendered in a test without stubbing the network.
 *
 * Requests go out together and land independently, so a slow query only holds
 * up its own panel. Errors are per slice for the same reason.
 */
export function useHealthStats(
  workflowId: string,
  projectId: string
): HealthState {
  const [state, setState] = useState<HealthState>({
    outcomes: null,
    outcomesError: null,
    signatures: null,
    signaturesError: null,
  });

  useEffect(() => {
    // React's strict mode double-invokes this effect in development, so a
    // response can land after the first pass has been torn down.
    const controller = new AbortController();

    const base = `/api/projects/${projectId}/workflows/${workflowId}/health`;

    const failed = (patch: Partial<HealthState>) => (error: unknown) => {
      // An abort is a teardown, not a failure — there is nobody left to tell.
      if (controller.signal.aborted) return;

      console.error('workflow health request failed:', error);
      setState(current => ({ ...current, ...patch }));
    };

    const message = 'Could not load workflow stats. Refresh to try again.';

    // Each slice is requested on its own and lands on its own, so a slow query
    // only holds up its own panel. Typed per request on purpose: a shared
    // helper would have to erase the payload type to build the patch
    // generically.
    void getJSON<Outcomes>(`${base}/outcomes`, controller.signal)
      .then(outcomes =>
        setState(current => ({ ...current, outcomes, outcomesError: null }))
      )
      .catch(failed({ outcomes: null, outcomesError: message }));

    void getJSON<FailureSignatures>(`${base}/failures`, controller.signal)
      .then(signatures =>
        setState(current => ({ ...current, signatures, signaturesError: null }))
      )
      .catch(failed({ signatures: null, signaturesError: message }));

    return () => {
      controller.abort();
    };
  }, [workflowId, projectId]);

  return state;
}
