import type { RelativePosition } from 'yjs';
import * as Y from 'yjs';
import type { TypedArray, TypedDoc, TypedMap } from 'yjs-types';

export interface AwarenessUser {
  clientId: number;
  user: {
    id: string;
    name: string;
    color: string;
  };
  cursor?: {
    x: number;
    y: number;
  };
  selection?: {
    anchor: RelativePosition;
    head: RelativePosition;
  };
}

export namespace Session {
  // TODO: note that we are using a 3rd party library to type the Yjs document.
  export type WorkflowDoc = TypedDoc<
    { workflow: TypedMap<Workflow> },
    {
      jobs: TypedArray<TypedMap<Job & { body: Y.Text }>>;
      edges: TypedArray<TypedMap<Edge>>;
    }
  >;

  export type Workflow = { id: string; name: string };

  export type Job = { id: string; name: string; body: string };

  // This could be a common type if we take the inner type out of Y.Map
  export type Edge = {
    id: string;
    condition_expression: string;
    condition_label: string;
    condition_type: string;
    enabled: boolean;
    source_job_id: string;
    source_trigger_id: string;
    target_job_id: string;
  };
}
