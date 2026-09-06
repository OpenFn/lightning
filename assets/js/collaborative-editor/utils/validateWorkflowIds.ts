/**
 * Rejects a workflow spec whose ids are objects rather than strings or null.
 *
 * The model occasionally emits an id as a nested mapping, which parses
 * without complaint and then corrupts entity identity on import. Anything
 * that imports model-produced YAML has to run this first; YAML this app
 * serialized itself does not need it.
 */
export function validateWorkflowIds(spec: Record<string, unknown>): void {
  if (spec['jobs']) {
    for (const [jobKey, job] of Object.entries(spec['jobs'] as object)) {
      const jobItem = job as Record<string, unknown>;
      if (
        jobItem['id'] &&
        typeof jobItem['id'] === 'object' &&
        jobItem['id'] !== null
      ) {
        throw new Error(
          `Invalid ID format for job "${jobKey}". IDs must be strings or null, not objects. ` +
            `Please ask the AI to regenerate the workflow with proper ID format.`
        );
      }
    }
  }
  if (spec['triggers']) {
    for (const [triggerKey, trigger] of Object.entries(
      spec['triggers'] as object
    )) {
      const triggerItem = trigger as Record<string, unknown>;
      if (
        triggerItem['id'] &&
        typeof triggerItem['id'] === 'object' &&
        triggerItem['id'] !== null
      ) {
        throw new Error(
          `Invalid ID format for trigger "${triggerKey}". IDs must be strings or null, not objects. ` +
            `Please ask the AI to regenerate the workflow with proper ID format.`
        );
      }
    }
  }
  if (spec['edges']) {
    for (const [edgeKey, edge] of Object.entries(spec['edges'] as object)) {
      const edgeItem = edge as Record<string, unknown>;
      if (
        edgeItem['id'] &&
        typeof edgeItem['id'] === 'object' &&
        edgeItem['id'] !== null
      ) {
        throw new Error(
          `Invalid ID format for edge "${edgeKey}". IDs must be strings or null, not objects. ` +
            `Please ask the AI to regenerate the workflow with proper ID format.`
        );
      }
    }
  }
}
