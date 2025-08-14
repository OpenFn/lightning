import type * as Y from "yjs";
import type { Session } from "./session";
import type { Trigger as TriggerType } from "./trigger";

// Generic store interface for Zustand stores with Immer middleware
export interface Store<T> {
  getState: () => T;
  setState: (partial: Partial<T> | ((state: T) => void)) => void;
  subscribe: (
    selector: (state: T) => any,
    listener: (selectedState: any, previousSelectedState: any) => void,
  ) => () => void;
}

// Legacy interface - will be replaced by Workflow.Store

export interface Workflow {
  name: string;
  jobs: Workflow.Job[];
  triggers: Workflow.Trigger[];
  edges: Workflow.Edge[];
}

export namespace Workflow {
  // Domain objects (keep existing Job, Trigger, Edge interfaces)
  export interface Job {
    id: string;
    name: string;
    body: string;
    adaptor: string;
    enabled: boolean;
    // ... other existing fields
  }

  export type Trigger = TriggerType;

  export interface Edge {
    id: string;
    source_job_id?: string;
    source_trigger_id?: string;
    target_job_id: string;
    condition?: string;
    // ... other existing fields
  }

  export type NodeType = "job" | "trigger" | "edge";

  export type Node = Job | Trigger | Edge;

  export interface Store {
    // React state - using Session types as that's what's implemented
    workflow: Workflow | null;
    jobs: Job[];
    edges: Edge[];
    triggers: Trigger[];
    selectedJobId: string | null;
    enabled: boolean | null;

    // Actions
    selectJob: (id: string | null) => void;
    connectToYjs: (bridge: YjsBridge) => void;
    getYjsBridge: () => YjsBridge | null;

    // Yjs-backed operations (matching actual implementation)
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
