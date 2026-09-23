import type { WorkOrderStateCounts } from './types';

/**
 * A link from this page into history, scoped to the workflow and to whatever
 * else the caller wants filtered.
 *
 * `log` is named so that history's four search-field buttons show what history
 * will actually search. Naming none of them puts the two out of step: the
 * server falls back to all four (`SearchParams.put_search_fields/2`) while the
 * buttons read an unnamed field as off. `log` on its own is how history opens
 * when you go there directly, from `init_filters/0`.
 */
export const historyUrl = (
  projectId: string,
  workflowId: string,
  filters: Record<string, string | readonly string[] | null | undefined>
) => {
  const params = new URLSearchParams({
    'filters[workflow_id]': workflowId,
    'filters[log]': 'true',
  });

  // Absent parts of a filter are skipped, so a caller can hand over an
  // optional field without guarding it. A list goes over as `key[]` repeated,
  // which is what Plug decodes back into a list for a `{:array, _}` field —
  // one joined string would fail to cast.
  for (const [key, value] of Object.entries(filters)) {
    if (Array.isArray(value)) {
      for (const item of value) params.append(`filters[${key}][]`, item);
    } else if (typeof value === 'string' && value) {
      params.set(`filters[${key}]`, value);
    }
  }

  return `/projects/${projectId}/history?${params.toString()}`;
};

/**
 * The history link for the states a slice stands for, over one window.
 *
 * History's status filter is a flag per state, so a slice that folded several
 * states together ticks all of them rather than naming a bucket history
 * doesn't have. A state history doesn't know is dropped server-side, leaving
 * the filter empty and the link showing every state under a wedge that counted
 * one — so the states are named by type rather than by string.
 */
export const stateUrl = (
  projectId: string,
  workflowId: string,
  from: string,
  ...states: (keyof WorkOrderStateCounts)[]
) =>
  historyUrl(projectId, workflowId, {
    date_after: from,
    ...Object.fromEntries(states.map(state => [state, 'true'])),
  });
