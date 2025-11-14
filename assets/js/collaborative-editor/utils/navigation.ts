/**
 * Navigation utilities for the collaborative editor
 *
 * Provides clean, testable navigation functions that build URLs from IDs
 * rather than parsing existing URLs. Uses URLSearchParams for query string
 * construction to avoid brittle string concatenation.
 *
 * **Important**: These utilities are for navigating to pages OUTSIDE the
 * collaborative editor (e.g., history page, run detail pages). For URL changes
 * within the collaborative editor itself, use the `useURLState` hook instead
 * to update query parameters without full page reloads.
 *
 * @see {@link ../hooks/use-url-state.ts} for in-editor URL state management
 */

/**
 * Navigate to the history page filtered by workflow ID
 *
 * @param projectId - The project UUID
 * @param workflowId - The workflow UUID
 *
 * @example
 * navigateToWorkflowHistory('proj-123', 'wf-456')
 * // Navigates to: /projects/proj-123/history?filters[workflow_id]=wf-456
 */
export function navigateToWorkflowHistory(
  projectId: string,
  workflowId: string
): void {
  const url = new URL(window.location.origin);
  url.pathname = `/projects/${projectId}/history`;

  const params = new URLSearchParams();
  params.set('filters[workflow_id]', workflowId);
  url.search = params.toString();

  window.location.assign(url.toString());
}

/**
 * Navigate to the history page filtered by work order ID
 *
 * @param projectId - The project UUID
 * @param workOrderId - The work order UUID
 *
 * @example
 * navigateToWorkOrderHistory('proj-123', 'wo-789')
 * // Navigates to: /projects/proj-123/history?filters[workorder_id]=wo-789
 */
export function navigateToWorkOrderHistory(
  projectId: string,
  workOrderId: string
): void {
  const url = new URL(window.location.origin);
  url.pathname = `/projects/${projectId}/history`;

  const params = new URLSearchParams();
  params.set('filters[workorder_id]', workOrderId);
  url.search = params.toString();

  window.location.assign(url.toString());
}

/**
 * Navigate to a specific run detail page
 *
 * @param projectId - The project UUID
 * @param runId - The run UUID
 *
 * @example
 * navigateToRun('proj-123', 'run-456')
 * // Navigates to: /projects/proj-123/runs/run-456
 */
export function navigateToRun(projectId: string, runId: string): void {
  const url = new URL(window.location.origin);
  url.pathname = `/projects/${projectId}/runs/${runId}`;

  window.location.assign(url.toString());
}
