import type { Channel } from 'phoenix';
import { useEffect, useState } from 'react';

import { channelRequest } from '#/collaborative-editor/hooks/useChannel';
import { useSocket } from '#/react/contexts/SocketProvider';

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
 * The `get_outcomes` reply from `LightningWeb.WorkflowHealthChannel`. Counts
 * only; `Lightning.Workflows.Stats` does the bucketing.
 *
 * One reply feeds both donuts: Outcomes folds the failure states together and
 * the failure breakdown slices them apart, and it is the same aggregate either
 * way — a second request would re-run the identical query.
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

/** The `get_failure_signatures` reply, heaviest signature first. */
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

/**
 * Joins `workflow_health:<id>` and fetches each chart's slice once.
 *
 * Kept apart from the components so charts stay pure functions of their props —
 * a chart can be rendered in a test without standing up a socket.
 *
 * Requests go out together and land independently, so a slow query only holds
 * up its own panel. Errors are per slice for the same reason.
 */
export function useHealthStats(
  workflowId: string,
  projectId: string
): HealthState {
  const { socket, isConnected, connectionError } = useSocket();
  const [state, setState] = useState<HealthState>({
    outcomes: null,
    outcomesError: null,
    signatures: null,
    signaturesError: null,
  });

  useEffect(() => {
    if (!socket || !isConnected) return;

    const channel: Channel = socket.channel(`workflow_health:${workflowId}`, {
      project_id: projectId,
    });

    // A reply can still land after `leave()` — and React's strict mode
    // double-invokes this effect in development, so it does.
    let live = true;

    const update = (patch: Partial<HealthState>) => {
      if (live) setState(current => ({ ...current, ...patch }));
    };

    // `channelRequest` rejects with a `ChannelRequestError` whose message is
    // already formatted from the server's payload.
    const reason = (error: unknown) =>
      error instanceof Error ? error.message : 'Could not load workflow stats';

    // Each slice is requested on its own and lands on its own, so a slow query
    // only holds up its own panel. Typed per event on purpose: a shared helper
    // would have to erase the payload type to build the patch generically.
    const load = () => {
      void channelRequest<Outcomes>(channel, 'get_outcomes', {})
        .then(outcomes => update({ outcomes, outcomesError: null }))
        .catch(e => update({ outcomes: null, outcomesError: reason(e) }));

      void channelRequest<FailureSignatures>(
        channel,
        'get_failure_signatures',
        {}
      )
        .then(signatures => update({ signatures, signaturesError: null }))
        .catch(e => update({ signatures: null, signaturesError: reason(e) }));
    };

    channel
      .join()
      .receive('ok', load)
      .receive('error', ({ reason }: { reason?: string }) => {
        // The guard's own words — "unauthorized", a params error — describe a
        // race or a bug, never something the reader can act on.
        console.error('workflow_health join rejected:', reason);

        const message = 'Could not load workflow stats. Refresh to try again.';
        update({ outcomesError: message, signaturesError: message });
      });

    return () => {
      live = false;
      channel.leave();
    };
  }, [socket, isConnected, workflowId, projectId]);

  // A dropped connection recovers on its own, so don't replace good numbers
  // with an error — only show it where nothing ever arrived.
  if (connectionError) {
    const message = 'Could not connect. Refresh to try again.';

    return {
      ...state,
      outcomesError: state.outcomes ? state.outcomesError : message,
      signaturesError: state.signatures ? state.signaturesError : message,
    };
  }

  return state;
}
