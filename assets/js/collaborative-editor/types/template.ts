export interface WorkflowTemplate {
  id: string;
  name: string;
  description: string | null;
  code: string;
  positions: Record<string, { x: number; y: number }> | null;
  tags: string[];
  workflow_id: string | null;
  inserted_at?: string;
  updated_at?: string;
}

export interface BaseTemplate {
  id: string;
  name: string;
  description: string;
  code: string;
  tags: string[];
  isBase: true;
}

export type Template = WorkflowTemplate | BaseTemplate;

/**
 * `isBase` is the only field that distinguishes the templates we ship from the
 * ones a user published, and the difference matters to the UI: base templates
 * are always listed, and are labelled so users can tell them apart.
 */
export function isBaseTemplate(template: Template): template is BaseTemplate {
  return 'isBase' in template && template.isBase;
}
