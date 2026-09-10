import { useEffect, useState } from 'react';

export interface Query<T> {
  data: T | null;
  error: string | null;
}

const MESSAGE = 'Could not load workflow stats. Refresh to try again.';

// Both fields null is the loading state: a request is out and nothing has
// answered it yet. A reply sets one or the other, so there is no fourth
// combination to name and no separate flag to keep in step with these two.
const EMPTY = { data: null, error: null };

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
  const [inFlight, setInFlight] = useState(true);
  const tick = usePollTick(inFlight);

  useEffect(() => {
    // A new url is a new question, so the last answer stops being an answer.
    // Without this the panel keeps drawing the previous range's numbers under
    // the new heading until the request lands — and since the panels answer at
    // their own speeds, the fast one would put the new window on screen beside
    // the slow one's old one.
    //
    // A tick is the *same* question asked again, which is why it is not in
    // here: the last answer stays on screen until the new one lands, rather
    // than the page blanking to "Loading…" every time the page re-reads.
    setState(EMPTY);
  }, [url]);

  useEffect(() => {
    // React's strict mode double-invokes this effect in development, so a
    // response can land after the first pass has been torn down.
    const controller = new AbortController();

    setInFlight(true);

    fetch(url, { credentials: 'same-origin', signal: controller.signal })
      .then(response => {
        if (!response.ok) throw new Error('Could not load workflow stats');

        return response.json() as Promise<T>;
      })
      .then(data => {
        // Same reason as the catch below: a reply that lands after the url
        // changed is an answer to a question nobody is asking any more.
        if (!controller.signal.aborted) setState({ data, error: null });

        return data;
      })
      // Ahead of the catch, not after it, so the chain still ends in one.
      .finally(() => {
        if (!controller.signal.aborted) setInFlight(false);
      })
      .catch((error: unknown) => {
        // An abort is a teardown, not a failure — there is nobody left to tell.
        if (controller.signal.aborted) return;

        console.error('workflow health request failed:', error);

        // A failed poll keeps the last answer — stale by an interval, not
        // wrong. Only a load with nothing to keep reports.
        setState(previous =>
          previous.data ? previous : { data: null, error: MESSAGE }
        );
      });

    return () => {
      controller.abort();
    };
  }, [url, tick]);

  return state;
}

// How long a settled work order can take to reach the screen. A poll that
// finds nothing changed costs one cheap query, not a recompute.
const POLL_MS = 30_000;

// There is no timer at all while a read is out: a read slower than the
// interval would otherwise be aborted by the tick behind it, and so never
// finish. Restarting when the read lands also measures the gap from the
// answer rather than from the request.
function usePollTick(inFlight: boolean): number {
  const [tick, setTick] = useState(0);

  useEffect(() => {
    if (inFlight) return;

    const bump = () => {
      if (!document.hidden) setTick(previous => previous + 1);
    };

    const interval = setInterval(bump, POLL_MS);

    // Coming back to the tab reads, however recently the last one answered:
    // someone who has just looked away and back wants what is true now, not
    // what was true up to half a minute ago. The cost is a marker query that
    // finds nothing moved, and the reader can only do this while watching.
    document.addEventListener('visibilitychange', bump);

    return () => {
      document.removeEventListener('visibilitychange', bump);
      clearInterval(interval);
    };
  }, [inFlight]);

  return tick;
}
