import type { Session } from "./session";

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

  export interface Trigger {
    id: string;
    name: string;
    type: string;
    // ... other existing fields
  }

  export interface Edge {
    id: string;
    source_job_id?: string;
    source_trigger_id?: string;
    target_job_id: string;
    condition?: string;
    // ... other existing fields
  }

  // Y.js escape hatch interface
  export interface YDocRefs {
    workflowMap: any; // Y.Map<any>
    getJobBodyText: (jobId: string) => any | null; // Y.Text | null
    getTriggerMap: (triggerId: string) => any | null; // Y.Map<any> | null
    getJobMap: (jobId: string) => any | null; // Y.Map<any> | null
  }

  export interface Store {
    // React state - using Session types as that's what's implemented
    workflow: Session.Workflow | null;
    jobs: Session.Job[];
    edges: Session.Edge[];
    selectedJobId: string | null;

    // Actions
    selectJob: (id: string | null) => void;
    connectToYjs: (bridge: any) => void;

    // Yjs-backed operations (matching actual implementation)
    getJobBodyYText: (id: string) => any; // Y.Text | null
    updateJobName: (id: string, name: string) => void;
    updateJobBody: (id: string, body: string) => void;
    addJob: (job: Partial<Session.Job>) => void;
    removeJob: (id: string) => void;
    updateJob: (id: string, updates: Partial<Session.Job>) => void;
  }
}
