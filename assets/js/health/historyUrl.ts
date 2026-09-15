/**
 * A link from this page into history, scoped to the workflow and to whatever
 * else the caller wants filtered.
 *
 * History only applies its own defaults to a visit that names no filters at
 * all, and every link from here names several. Without `log`, arriving drops
 * the one search field a normal history visit starts with, and the first
 * search term typed into the box matches nothing with every toggle visibly
 * off.
 */
export const historyUrl = (
  projectId: string,
  workflowId: string,
  filters: Record<string, string | null | undefined>
) => {
  const params = new URLSearchParams({
    'filters[workflow_id]': workflowId,
    'filters[log]': 'true',
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
  return (...states: string[]) =>
    historyUrl(projectId, workflowId, {
      date_after: from,
      ...Object.fromEntries(states.map(state => [state, 'true'])),
    });
};
