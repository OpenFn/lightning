import type { PhoenixChannelProvider } from 'y-phoenix-channel';
import * as z from 'zod';

import { isoDateTimeSchema, uuidSchema } from './common';

export const UserContextSchema = z.object({
  id: uuidSchema,
  first_name: z.string(),
  last_name: z.string(),
  email: z.string().email(),
  email_confirmed: z.boolean(),
  support_user: z.boolean(),
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
  auth_type: z.enum(['basic', 'api']),
});

export type WebhookAuthMethod = z.infer<typeof WebhookAuthMethodSchema>;

export const VersionSchema = z.object({
  lock_version: z.number().int(),
  inserted_at: z.string(),
  is_latest: z.boolean(),
});

export type Version = z.infer<typeof VersionSchema>;

export const WorkflowTemplateSchema = z.object({
  id: uuidSchema,
  name: z.string(),
  description: z.string().nullable(),
  tags: z.array(z.string()),
  workflow_id: uuidSchema,
  code: z.string(),
  positions: z.record(
    z.string(),
    z.object({
      x: z.number(),
      y: z.number(),
    })
  ),
});

export type WorkflowTemplate = z.infer<typeof WorkflowTemplateSchema>;

export const LimitInfoSchema = z.object({
  allowed: z.boolean(),
  message: z.string().nullable(),
});

export type LimitInfo = z.infer<typeof LimitInfoSchema>;

export const LimitsSchema = z.object({
  runs: LimitInfoSchema.optional(),
});

export type Limits = z.infer<typeof LimitsSchema>;

export const SessionContextResponseSchema = z.object({
  user: UserContextSchema.nullable(),
  project: ProjectContextSchema.nullable(),
  config: AppConfigSchema,
  permissions: PermissionsSchema,
  latest_snapshot_lock_version: z.number().int().nullable(),
  project_repo_connection: ProjectRepoConnectionSchema.nullable(),
  webhook_auth_methods: z.array(WebhookAuthMethodSchema),
  workflow_template: WorkflowTemplateSchema.nullable(),
  has_read_ai_disclaimer: z.boolean(),
  limits: LimitsSchema.optional(),
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
  versions: Version[];
  versionsLoading: boolean;
  versionsError: string | null;
  workflow_template: WorkflowTemplate | null;
  hasReadAIDisclaimer: boolean;
  limits: Limits;
  isNewWorkflow: boolean;
  isLoading: boolean;
  error: string | null;
  lastUpdated: number | null;
  saveInProgress: boolean;
}

interface SessionContextCommands {
  requestSessionContext: () => Promise<void>;
  requestVersions: () => Promise<void>;
  clearVersions: () => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  clearError: () => void;
  setLatestSnapshotLockVersion: (lockVersion: number) => void;
  clearIsNewWorkflow: () => void;
  setHasReadAIDisclaimer: (hasRead: boolean) => void;
  getLimits: (actionType: 'new_run') => Promise<void>;
  setSaveInProgress: (inProgress: boolean) => void;
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
