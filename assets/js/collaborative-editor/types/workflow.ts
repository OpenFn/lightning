/**
 * TypeScript interfaces for the collaborative workflow editor system
 */

import type { AwarenessUser } from './session';

export interface WorkflowJob {
  id: string;
  name: string;
  body: string;
}

export interface Workflow {
  id: string;
  name: string;
}

export interface WorkflowStore {
  workflow: Workflow | null;
  jobs: WorkflowJob[];
  selectedJobId: string | null;
  selectJob: (id: string | null) => void;
  updateJobName: (id: string, name: string) => void;
  updateJobBody: (id: string, body: string) => void;
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
