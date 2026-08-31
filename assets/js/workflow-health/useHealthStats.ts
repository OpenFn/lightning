import type { Channel } from 'phoenix';
import { useEffect, useState } from 'react';

import { channelRequest } from '#/collaborative-editor/hooks/useChannel';
import { useSocket } from '#/react/contexts/SocketProvider';

/**
 * The `get_outcomes` reply from `LightningWeb.WorkflowHealthChannel`. Counts
 * only; `Lightning.Workflows.Stats` does the bucketing.
 */
export interface Outcomes {
  window: { from: string; to: string };
  counts: { success: number; failed: number; pending: number };
}

interface HealthState {
  outcomes: Outcomes | null;
  error: string | null;
}

/**
 * Joins `workflow_health:<id>` and fetches the outcomes chart's counts once.
 *
 * Kept apart from the components so charts stay pure functions of their props —
 * a chart can be rendered in a test without standing up a socket.
 *
 * ponytail: one chart, so join and request live in one hook. Chart #2 splits
 * this into a hook owning the join plus one request hook per chart, so a slow
 * query only blocks its own chart.
 */
export function useHealthStats(
  workflowId: string,
  projectId: string
): HealthState {
  const { socket, isConnected, connectionError } = useSocket();
  const [state, setState] = useState<HealthState>({
    outcomes: null,
    error: null,
  });

  useEffect(() => {
    if (!socket || !isConnected) return;

    const channel: Channel = socket.channel(`workflow_health:${workflowId}`, {
      project_id: projectId,
    });

    // A reply can still land after `leave()` — and React's strict mode
    // double-invokes this effect in development, so it does.
    let live = true;

    const fail = (message: string) => {
      if (live) setState({ outcomes: null, error: message });
    };

    const load = async () => {
      try {
        const outcomes = await channelRequest<Outcomes>(
          channel,
          'get_outcomes',
          {}
        );
        if (live) setState({ outcomes, error: null });
      } catch (error) {
        // `channelRequest` rejects with a `ChannelRequestError` whose message is
        // already formatted from the server's payload.
        fail(
          error instanceof Error
            ? error.message
            : 'Could not load workflow stats'
        );
      }
    };

    channel
      .join()
      .receive('ok', () => {
        void load();
      })
      .receive('error', ({ reason }: { reason?: string }) => {
        fail(reason ?? 'Could not load workflow stats');
      });

    return () => {
      live = false;
      channel.leave();
    };
  }, [socket, isConnected, workflowId, projectId]);

  // A dropped connection recovers on its own, so don't replace good numbers
  // with an error — only show it if we never got any.
  if (connectionError && !state.outcomes) {
    return {
      outcomes: null,
      error: 'Could not connect. Refresh to try again.',
    };
  }

  return state;
}
