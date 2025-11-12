/* eslint-disable @typescript-eslint/no-namespace */
import type * as Y from "yjs";
import type { TypedArray, TypedDoc, TypedMap } from "yjs-types";

import type { Workflow as WorkflowType } from "./workflow";

// Why isn't this used anywhere, it definity was!
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
    anchor: Y.RelativePosition;
    head: Y.RelativePosition;
  };
}

export namespace Session {
  // TODO: note that we are using a 3rd party library to type the Yjs document.
  export type WorkflowDoc = TypedDoc<
    {
      workflow: TypedMap<Workflow>;
      positions: TypedMap<WorkflowType.Positions>;
      errors: TypedMap<{
        workflow?: Record<string, string[]>;
        jobs?: Record<string, Record<string, string[]>>;
        triggers?: Record<string, Record<string, string[]>>;
        edges?: Record<string, Record<string, string[]>>;
      }>;
    },
    {
      jobs: TypedArray<TypedMap<Job & { body: Y.Text }>>;
      edges: TypedArray<TypedMap<Edge>>;
      triggers: TypedArray<TypedMap<Trigger>>;
    }
  >;

  // TODO: update with extra fields from the server
  export type Workflow = {
    id: string;
    name: string;
    lock_version: number | null;
    deleted_at: string | null;
    concurrency: number | null;
    enable_job_logs: boolean;
    errors?: Record<string, string[]>;
  };

  export type Job = {
    id: string;
    name: string;
    body: string;
    adaptor: string;
    enabled: boolean;
    project_credential_id: string | null;
    keychain_credential_id: string | null;
    errors?: Record<string, string[]>;
  };

  export type Trigger = {
    id: string;
    type: string;
    enabled: boolean;
    cron_expression: string | null;
    has_auth_method: boolean;
    webhook_auth_methods: Array<{
      id: string;
      name: string;
      auth_type: string;
    }> | null;
    errors?: Record<string, string[]>;
  };

  // This could be a common type if we take the inner type out of Y.Map
  export type Edge = {
    id: string;
    workflow_id: string;
    condition_expression: string | null;
    condition_label: string | null;
    condition_type: string;
    enabled: boolean;
    source_job_id: string | null;
    source_trigger_id: string | null;
    target_job_id: string;
    errors?: Record<string, string[]>;
  };
}

/* eslint-enable @typescript-eslint/no-namespace */
