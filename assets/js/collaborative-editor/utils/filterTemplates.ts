import type { WorkflowTemplate } from '../types/template';

/**
 * Case-insensitive substring match against a template's name, description,
 * or tags. The query is lowercased here, so callers may pass it raw.
 */
export function matchesQuery(
  t: { name: string; description: string | null; tags: string[] },
  q: string
): boolean {
  const needle = q.toLowerCase();

  return (
    t.name.toLowerCase().includes(needle) ||
    (t.description?.toLowerCase().includes(needle) ?? false) ||
    t.tags.some(tag => tag.toLowerCase().includes(needle))
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
