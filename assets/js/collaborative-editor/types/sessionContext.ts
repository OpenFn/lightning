import type { PhoenixChannelProvider } from "y-phoenix-channel";
import * as z from "zod";

import { isoDateTimeSchema, uuidSchema } from "./common";

export const UserContextSchema = z.object({
  id: uuidSchema,
  first_name: z.string(),
  last_name: z.string(),
  email: z.string().email(),
  email_confirmed: z.boolean(),
  inserted_at: isoDateTimeSchema,
});

export const ProjectContextSchema = z.object({
  id: uuidSchema,
  name: z.string(),
  env: z.string().nullable().optional(),
});

export const ProjectRepoConnectionSchema = z.object({
  id: uuidSchema,
  repo: z.string(),
  branch: z.string(),
  github_installation_id: z.string(),
});

export const AppConfigSchema = z.object({
  require_email_verification: z.boolean(),
});

export const PermissionsSchema = z.object({
  can_edit_workflow: z.boolean(),
  can_run_workflow: z.boolean(),
  can_write_webhook_auth_method: z.boolean(),
});

export type Permissions = z.infer<typeof PermissionsSchema>;

export const WebhookAuthMethodSchema = z.object({
  id: uuidSchema,
  name: z.string(),
  auth_type: z.enum(["basic", "api"]),
});

export type WebhookAuthMethod = z.infer<typeof WebhookAuthMethodSchema>;

export const SessionContextResponseSchema = z.object({
  user: UserContextSchema.nullable(),
  project: ProjectContextSchema.nullable(),
  config: AppConfigSchema,
  permissions: PermissionsSchema,
  latest_snapshot_lock_version: z.number().int(),
  project_repo_connection: ProjectRepoConnectionSchema.nullable(),
  webhook_auth_methods: z.array(WebhookAuthMethodSchema),
});

export type UserContext = z.infer<typeof UserContextSchema>;
export type ProjectContext = z.infer<typeof ProjectContextSchema>;
export type ProjectRepoConnection = z.infer<typeof ProjectRepoConnectionSchema>;
export type AppConfig = z.infer<typeof AppConfigSchema>;

export interface SessionContextState {
  user: UserContext | null;
  project: ProjectContext | null;
  config: AppConfig | null;
  permissions: Permissions | null;
  latestSnapshotLockVersion: number | null;
  projectRepoConnection: ProjectRepoConnection | null;
  webhookAuthMethods: WebhookAuthMethod[];
  isNewWorkflow: boolean;
  isLoading: boolean;
  error: string | null;
  lastUpdated: number | null;
}

interface SessionContextCommands {
  requestSessionContext: () => Promise<void>;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  clearError: () => void;
  setLatestSnapshotLockVersion: (lockVersion: number) => void;
  clearIsNewWorkflow: () => void;
}

interface SessionContextQueries {
  getSnapshot: () => SessionContextState;

  subscribe: (listener: () => void) => () => void;
  withSelector: <T>(selector: (state: SessionContextState) => T) => () => T;
}

interface SessionContextStoreInternals {
  _connectChannel: (provider: PhoenixChannelProvider) => () => void;
}

export type SessionContextStore = SessionContextQueries &
  SessionContextCommands &
  SessionContextStoreInternals;
