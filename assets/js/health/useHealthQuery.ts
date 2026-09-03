import { useEffect, useState } from 'react';

interface Query<T> {
  data: T | null;
  error: string | null;
}

const MESSAGE = 'Could not load workflow stats. Refresh to try again.';

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
  const [state, setState] = useState<Query<T>>({ data: null, error: null });

  useEffect(() => {
    // A new url is a new question, so the last answer stops being an answer.
    // Without this the panel keeps drawing the previous range's numbers under
    // the new heading until the request lands.
    setState({ data: null, error: null });

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
        if (!controller.signal.aborted) setState({ data, error: null });

        return data;
      })
      .catch((error: unknown) => {
        // An abort is a teardown, not a failure — there is nobody left to tell.
        if (controller.signal.aborted) return;

        console.error('workflow health request failed:', error);
        setState({ data: null, error: MESSAGE });
      });

    return () => {
      controller.abort();
    };
  }, [url]);

  return state;
}
