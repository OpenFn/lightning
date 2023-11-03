import type * as ReactFlow from 'reactflow';

// This all describes the lightning view of a workflow
export namespace Lightning {
  export interface Node {
    id: string;
    name: string;
    workflow_id: string;

    // Not technically from Lightning, but we'll infer this and scribble it
    placeholder?: boolean;
  }

  export interface CronTrigger extends Node {
    type: 'cron';
    cron_expression: string;
  }

  export interface WebhookTrigger extends Node {
    has_auth_method: boolean;
    type: 'webhook';
    webhook_url: string;
  }

  export type TriggerNode = CronTrigger | WebhookTrigger;

  export interface JobNode extends Node {
    body?: string;
    adaptor?: string;
  }

  export interface Edge {
    id: string;
    source_job_id?: string;
    source_trigger_id?: string;
    target_job_id?: string;
    name: string;
    enabled?: boolean;
    condition?: string;
    error_path?: boolean;
    errors: any;
  }

  export type Workflow = {
    id?: string;
    changeId?: string;
    triggers: TriggerNode[];
    jobs: JobNode[];
    edges: Edge[];
  };
}

export namespace Flow {
  export type Node = ReactFlow.Node;

  export type Edge = ReactFlow.Edge;

  export type Model = {
    nodes: Node[];
    edges: Edge[];
  };
}

export type Positions = {
  [nodeId: string]: { x: number; y: number };
};
