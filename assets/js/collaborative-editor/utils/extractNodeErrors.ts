/**
 * Extracts nested entity errors from WorkflowStore state.
 *
 * The state.errors object has this structure:
 * {
 *   // Workflow-level errors
 *   name: ["can't be blank"],
 *
 *   // Entity errors (nested)
 *   jobs: {
 *     "job-uuid-123": {
 *       name: ["can't be blank"],
 *       adaptor: ["invalid format"]
 *     }
 *   },
 *   edges: {
 *     "edge-uuid-456": {
 *       condition_expression: ["is invalid"]
 *     }
 *   },
 *   triggers: {
 *     "trigger-uuid-789": {
 *       cron_expression: ["must be valid"]
 *     }
 *   }
 * }
 *
 * This function extracts the nested entity errors and returns them
 * grouped by type.
 */

export interface NodeErrors {
  jobs: Record<string, Record<string, string[]>>;
  edges: Record<string, Record<string, string[]>>;
  triggers: Record<string, Record<string, string[]>>;
}

export function extractNodeErrors(
  errors: Record<string, any>
): NodeErrors {
  return {
    jobs:
      (errors.jobs as Record<string, Record<string, string[]>>) || {},
    edges:
      (errors.edges as Record<string, Record<string, string[]>>) || {},
    triggers:
      (errors.triggers as Record<string, Record<string, string[]>>) ||
      {},
  };
}
