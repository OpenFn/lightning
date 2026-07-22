import type { WorkflowTemplate } from '../types/template';

/**
 * Case-insensitive substring match against a template's name, description,
 * or tags. Callers are expected to pass a pre-lowercased query `q`.
 */
export function matchesQuery(
  t: { name: string; description: string | null; tags: string[] },
  q: string
): boolean {
  return (
    t.name.toLowerCase().includes(q) ||
    (t.description?.toLowerCase().includes(q) ?? false) ||
    t.tags.some(tag => tag.toLowerCase().includes(q))
  );
}

/**
 * Filters templates by a search query, matching on name, description, or
 * tags. Returns all templates when the query is empty.
 */
export function filterTemplates(
  templates: WorkflowTemplate[],
  q: string
): WorkflowTemplate[] {
  if (!q) return templates;
  return templates.filter(t => matchesQuery(t, q));
}
