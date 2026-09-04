import { useEffect, useState } from 'react';

export interface Query<T> {
  data: T | null;
  error: string | null;
  /** When the data on screen was fetched, or null while there is none. */
  fetchedAt: Date | null;
  loading: boolean;
}

const MESSAGE = 'Could not load workflow stats. Refresh to try again.';

const EMPTY = { data: null, error: null, fetchedAt: null, loading: true };

/** Base path for one workflow's health endpoints. */
export const healthBase = (projectId: string, workflowId: string) =>
  `/api/projects/${projectId}/workflows/${workflowId}/health`;

/**
 * Fetches one health endpoint.
 *
 * Called once per endpoint — the two donuts share the `outcomes` reply — so
 * this hook's interface doesn't grow when charts do.
 * Kept apart from the components so charts stay pure functions of their props —
 * a chart can be rendered in a test without stubbing the network.
 *
 * Each call owns its request and its state, so a slow or broken query only
 * holds up its own panel.
 */
export function useHealthQuery<T>(url: string): Query<T> {
  const [state, setState] = useState<Query<T>>(EMPTY);
  const tick = useHealthChanged();

  useEffect(() => {
    // A new url is a new question, so the last answer stops being an answer.
    // Without this the panel keeps drawing the previous range's numbers under
    // the new heading until the request lands — and since the panels answer at
    // their own speeds, the fast one would put the new window on screen beside
    // the slow one's old one.
    //
    // A tick is the *same* question asked again, which is why it is not in
    // here: the last answer stays on screen until the new one lands, rather
    // than the page blanking to "Loading…" every time a work order finishes.
    setState(EMPTY);
  }, [url]);

  useEffect(() => {
    // React's strict mode double-invokes this effect in development, so a
    // response can land after the first pass has been torn down.
    const controller = new AbortController();

    fetch(url, { credentials: 'same-origin', signal: controller.signal })
      .then(response => {
        if (!response.ok) throw new Error('Could not load workflow stats');

        return response.json() as Promise<T>;
      })
      .then(data => {
        // Same reason as the catch below: a reply that lands after the url
        // changed is an answer to a question nobody is asking any more.
        if (!controller.signal.aborted) {
          setState({
            data,
            error: null,
            fetchedAt: new Date(),
            loading: false,
          });
        }

        return data;
      })
      .catch((error: unknown) => {
        // An abort is a teardown, not a failure — there is nobody left to tell.
        if (controller.signal.aborted) return;

        console.error('workflow health request failed:', error);

        setState({
          data: null,
          error: MESSAGE,
          fetchedAt: null,
          loading: false,
        });
      });

    return () => {
      controller.abort();
    };
  }, [url, tick]);

  return state;
}

/**
 * Counts `health:changed` pushes from the health LiveView.
 *
 * There is no polling here. The LiveView subscribes to this workflow's work
 * order events and throttles them, so a tick means the numbers actually moved
 * — a workflow that nothing is running makes no requests at all.
 *
 * LiveView dispatches every `push_event` on `window` as `phx:<name>`, so this
 * needs nothing from the `ReactComponent` hook that mounts the page.
 */
function useHealthChanged(): number {
  const [tick, setTick] = useState(0);

  useEffect(() => {
    const bump = () => {
      setTick(previous => previous + 1);
    };

    window.addEventListener('phx:health:changed', bump);

    return () => {
      window.removeEventListener('phx:health:changed', bump);
    };
  }, []);

  return tick;
}
