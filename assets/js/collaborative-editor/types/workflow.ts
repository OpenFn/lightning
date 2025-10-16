/* eslint-disable @typescript-eslint/no-namespace */
// What should we do about this?

/**
 * Updated workflow types following useSyncExternalStore + Immer + Y.Doc pattern
 * Provides referentially stable state management with clear separation between
 * collaborative data (Y.Doc sourced) and local UI state.
 */

import type * as Y from "yjs";

import type { Job as JobType } from "./job";
import type { Session } from "./session";
import type { Trigger as TriggerType } from "./trigger";

export interface Workflow {
  name: string;
  jobs: Workflow.Job[];
  triggers: Workflow.Trigger[];
  edges: Workflow.Edge[];
  positions: Workflow.Positions;
}

export namespace Workflow {
  // Domain objects - use comprehensive Job type from job.ts
  export type Job = JobType;

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
  }

  export type NodeType = "job" | "trigger" | "edge";
  export type Node = Job | Trigger | Edge;

  export type Positions = Record<string, { x: number; y: number }>;

  export interface State {
    // Y.Doc sourced data (synced via observers)
    workflow: Session.Workflow | null;
    jobs: Workflow.Job[];
    triggers: Workflow.Trigger[];
    edges: Workflow.Edge[];
    positions: Workflow.Positions;

    // Local UI state
    selectedJobId: string | null;
    selectedTriggerId: string | null;
    selectedEdgeId: string | null;

    // Computed/derived state
    enabled: boolean | null; // Computed from triggers
    selectedNode: Workflow.Job | Workflow.Trigger | null;
    selectedEdge: Workflow.Edge | null;
  }

  export interface Actions {
    // Pattern 1: Y.Doc update → observer → immer update
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

    // Workflow save operation
    saveWorkflow: () => Promise<{
      saved_at?: string;
      lock_version?: number;
    } | null>;

    // Workflow reset operation
    resetWorkflow: () => Promise<void>;
  }
}

/* eslint-enable @typescript-eslint/no-namespace */
