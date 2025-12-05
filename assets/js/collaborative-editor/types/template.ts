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
