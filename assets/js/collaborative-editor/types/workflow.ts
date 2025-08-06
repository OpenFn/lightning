/**
 * TypeScript interfaces for the collaborative workflow editor system
 */

import type { AwarenessUser } from './session';
import type * as Y from 'yjs';

// Job data structure as plain JS object (for React state)
export interface WorkflowJobData {
  id: string;
  name: string;
  body: string; // For display purposes, actual body is Y.Text
}

export interface Workflow {
  id: string;
  name: string;
}

export interface WorkflowStore {
  workflow: Workflow | null;
  jobs: WorkflowJobData[]; // React state uses plain JS objects for display
  selectedJobId: string | null;
  selectJob: (id: string | null) => void;
  updateJobName: (id: string, name: string) => void;
  updateJobBody: (id: string, body: string) => void;
  getJobBodyYText: (id: string) => Y.Text | null;
  getYjsJob: (id: string) => YjsWorkflowJob | null; // Access to actual Y.Map
  users: AwarenessUser[];
  isConnected: boolean;
  isSynced: boolean;
}

export interface YjsCollaborativeHookEvents {
  yjs_update: (message: any) => void;
  yjs_awareness: (message: any) => void;
  sync_request: (message: any) => void;
  yjs_response: (message: any) => void;
  yjs_query_awareness: (message: any) => void;
}

// Data attributes passed from LiveView template to React component
// TODO: where should this go, not in here thats for sure.
export interface CollaborativeEditorDataProps {
  'data-workflow-id': string;
  'data-workflow-name': string;
  'data-user-id': string;
  'data-user-name': string;
}
