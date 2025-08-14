/**
 * Updated workflow types following useSyncExternalStore + Immer + Y.Doc pattern
 * Provides referentially stable state management with clear separation between
 * collaborative data (Y.Doc sourced) and local UI state.
 */

import type * as Y from "yjs";
import type { AwarenessUser, Session } from "./session";
import type { Trigger as TriggerType } from "./trigger";

export namespace Workflow {
  // Domain objects (existing interfaces, kept for compatibility)
  export interface Job {
    id: string;
    name: string;
    body: string;
    adaptor: string;
    enabled: boolean;
    // ... other existing fields can be added as needed
  }

  export type Trigger = TriggerType;

  export interface Edge {
    id: string;
    source_job_id?: string;
    source_trigger_id?: string;
    target_job_id: string;
    condition?: string;
    condition_type?: string;
    condition_expression?: string;
    condition_label?: string;
    enabled?: boolean;
    // ... other existing fields
  }

  export type NodeType = "job" | "trigger" | "edge";
  export type Node = Job | Trigger | Edge;

  // New referentially stable state interface following context document
  export interface WorkflowState {
    // Y.Doc sourced data (synced via observers)
    workflow: Session.Workflow | null;
    jobs: Workflow.Job[];
    triggers: Workflow.Trigger[];
    edges: Workflow.Edge[];

    // Local UI state
    selectedJobId: string | null;
    selectedTriggerId: string | null;
    selectedEdgeId: string | null;

    // Computed/derived state
    enabled: boolean | null; // Computed from triggers
    selectedNode: Workflow.Job | Workflow.Trigger | null;
    selectedEdge: Workflow.Edge | null;
    isCollaborating: boolean;
    connectedUsers: AwarenessUser[];
  }

  export interface WorkflowActions {
    // Pattern 1: Y.Doc update � observer � immer update
    updateJob: (id: string, updates: Partial<Session.Job>) => void;
    updateJobName: (id: string, name: string) => void;
    updateJobBody: (id: string, body: string) => void;
    addJob: (job: Partial<Session.Job>) => void;
    removeJob: (id: string) => void;
    updateTrigger: (id: string, updates: Partial<Session.Trigger>) => void;
    setEnabled: (enabled: boolean) => void;

    // Pattern 3: Direct immer update only (local UI state)
    selectJob: (id: string | null) => void;
    selectTrigger: (id: string | null) => void;
    selectEdge: (id: string | null) => void;
    clearSelection: () => void;

    // Pattern 2: Y.Doc + immediate immer update (rare)
    removeJobAndClearSelection: (id: string) => void;

    // Y.js specific operations
    getJobBodyYText: (id: string) => Y.Text | null;
  }

  // Legacy Store interface - keep for backward compatibility during migration
  export interface Store {
    workflow: Workflow.Job | null; // This seems wrong in original, keeping for compatibility
    jobs: Job[];
    edges: Edge[];
    triggers: Trigger[];
    selectedJobId: string | null;
    enabled: boolean | null;

    // Legacy actions - keep for backward compatibility
    selectJob: (id: string | null) => void;
    connectToYjs: (bridge: YjsBridge) => void;
    getYjsBridge: () => YjsBridge | null;
    getJobBodyYText: (id: string) => Y.Text | null;
    updateJobName: (id: string, name: string) => void;
    updateJobBody: (id: string, body: string) => void;
    addJob: (job: Partial<Session.Job>) => void;
    removeJob: (id: string) => void;
    updateJob: (id: string, updates: Partial<Session.Job>) => void;
    updateTrigger: (id: string, updates: Partial<Session.Trigger>) => void;
    setEnabled: (enabled: boolean) => void;
  }
}

// Legacy YjsBridge interface - keep for backward compatibility
export interface YjsBridge {
  workflowMap: Y.Map<unknown>;
  jobsArray: Y.Array<Y.Map<unknown>>;
  edgesArray: Y.Array<Y.Map<unknown>>;
  triggersArray: Y.Array<Y.Map<unknown>>;
  getYjsJob: (id: string) => Y.Map<unknown> | null;
  getJobBodyText: (id: string) => Y.Text | null;
  getYjsTrigger: (id: string) => Y.Map<unknown> | null;
  updateTrigger: (id: string, updates: Partial<Session.Trigger>) => void;
  setEnabled: (enabled: boolean) => void;
}
