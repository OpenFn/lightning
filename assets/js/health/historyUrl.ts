import type { WorkOrderStateCounts } from './types';

/**
 * A link from this page into history, scoped to the workflow and to whatever
 * else the caller wants filtered.
 *
 * No search field is named. History reads the four of them as a set: name one
 * and the other three arrive switched off, name none and the default — all
 * four — stands. See `SearchParams.put_search_fields/2`.
 */
export const historyUrl = (
  projectId: string,
  workflowId: string,
  filters: Record<string, string | null | undefined>
) => {
  const params = new URLSearchParams({
    'filters[workflow_id]': workflowId,
  });

  // Absent parts of a filter are skipped, so a caller can hand over an
  // optional field without guarding it.
  for (const [key, value] of Object.entries(filters)) {
    if (value) params.set(`filters[${key}]`, value);
  }

  return `/projects/${projectId}/history?${params.toString()}`;
};

/**
 * Returns a link builder bound to one workflow and window: call it with the
 * states a slice stands for and it gives back that slice's history link.
 *
 * History's status filter is a flag per state, so a slice that folded several
 * states together ticks all of them rather than naming a bucket history
 * doesn't have.
 */
export const stateUrls = (
  projectId: string,
  workflowId: string,
  from: string
) => {
  // A state history doesn't know is dropped server-side, leaving the status
  // filter empty and the link showing every state under a wedge that counted
  // one — so the states are named by type rather than by string.
  return (...states: (keyof WorkOrderStateCounts)[]) =>
    historyUrl(projectId, workflowId, {
      date_after: from,
      ...Object.fromEntries(states.map(state => [state, 'true'])),
    });
};
