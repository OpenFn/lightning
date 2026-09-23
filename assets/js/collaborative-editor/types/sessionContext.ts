import type { PhoenixChannelProvider } from 'y-phoenix-channel';
import * as z from 'zod';

import { isoDateTimeSchema, uuidSchema } from './common';
import { BaseWorkflowSchema, type BaseWorkflow } from './workflow';

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
  concurrency: z.number().int().nullable().optional(),
  env: z.string().nullable().optional(),
  is_sandbox: z.boolean().optional(),
});

export const ProjectRepoConnectionSchema = z.object({
  id: uuidSchema,
  repo: z.string(),
  branch: z.string(),
  github_installation_id: z.string(),
});

export const AppConfigSchema = z.object({
  require_email_verification: z.boolean(),
  max_dataclip_size_bytes: z.number().int().optional(),
});

export const PermissionsSchema = z.object({
  can_edit_workflow: z.boolean(),
  can_run_workflow: z.boolean(),
  can_write_webhook_auth_method: z.boolean(),
  can_provision_sandbox: z.boolean().optional().default(false),
  can_archive_sandbox: z.boolean().optional().default(false),
});

export type Permissions = z.infer<typeof PermissionsSchema>;

export const WebhookAuthMethodSchema = z.object({
  id: uuidSchema,
  name: z.string(),
  auth_type: z.enum(['basic', 'api']),
});

export type WebhookAuthMethod = z.infer<typeof WebhookAuthMethodSchema>;

export const ReleaseSchema = z.object({
  version_number: z.number().int(),
  kind: z.string(),
  inserted_at: z.string(),
  published_by: z.string().nullable(),
  source_project: z.string().nullable(),
  lock_version: z.number().int(),
  snapshot_id: z.string().nullish().default(null),
  restored_from_version_number: z.number().int().nullish().default(null),
  is_latest: z.boolean(),
});

export type Release = z.infer<typeof ReleaseSchema>;

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
  positions: z
    .record(
      z.string(),
      z.object({
        x: z.number(),
        y: z.number(),
      })
    )
    .nullable(),
});

export type WorkflowTemplate = z.infer<typeof WorkflowTemplateSchema>;

export const LimitInfoSchema = z.object({
  allowed: z.boolean(),
  message: z.string().nullable(),
});

export type LimitInfo = z.infer<typeof LimitInfoSchema>;

export const LimitsSchema = z.object({
  runs: LimitInfoSchema.optional(),
  workflow_activation: LimitInfoSchema.optional(),
  github_sync: LimitInfoSchema.optional(),
  ai_assistant: LimitInfoSchema.optional(),
  new_sandbox: LimitInfoSchema.optional(),
});

export type Limits = z.infer<typeof LimitsSchema>;

export const SessionContextResponseSchema = z.object({
  user: UserContextSchema.nullable(),
  project: ProjectContextSchema.nullable(),
  config: AppConfigSchema,
  permissions: PermissionsSchema,
  content_locked: z.boolean().optional().default(false),
  latest_snapshot_lock_version: z.number().int().nullable(),
  latest_snapshot_id: z.string().nullable().optional(),
  project_repo_connection: ProjectRepoConnectionSchema.nullable(),
  webhook_auth_methods: z.array(WebhookAuthMethodSchema),
  workflow_template: WorkflowTemplateSchema.nullable(),
  suppress_enable_trigger_warning: z.boolean().optional().default(false),
  experimental_features_enabled: z.boolean().optional().default(false),
  limits: LimitsSchema.optional(),
  workflow: BaseWorkflowSchema.optional(),
});

export type UserContext = z.infer<typeof UserContextSchema>;
export type ProjectContext = z.infer<typeof ProjectContextSchema>;
export type ProjectRepoConnection = z.infer<typeof ProjectRepoConnectionSchema>;
export type AppConfig = z.infer<typeof AppConfigSchema>;

export interface SessionContextState {
  user: UserContext | null;
  project: ProjectContext | null;
  workflow: BaseWorkflow | null;
  config: AppConfig | null;
  permissions: Permissions | null;
  contentLocked: boolean;
  experimentalFeaturesEnabled: boolean;
  latestSnapshotLockVersion: number | null;
  latestSnapshotId: string | null;
  projectRepoConnection: ProjectRepoConnection | null;
  webhookAuthMethods: WebhookAuthMethod[];
  releases: Release[];
  releasesLoaded: boolean;
  releasesLoading: boolean;
  releasesError: string | null;
  versions: Version[];
  versionsLoaded: boolean;
  versionsLoading: boolean;
  versionsError: string | null;
  workflow_template: WorkflowTemplate | null;
  suppressEnableTriggerWarning: boolean;
  limits: Limits;
  isNewWorkflow: boolean;
  isLoading: boolean;
  error: string | null;
  lastUpdated: number | null;
}

interface SessionContextCommands {
  requestSessionContext: () => Promise<void>;
  requestReleases: () => Promise<void>;
  clearReleases: () => void;
  requestVersions: () => Promise<void>;
  clearVersions: () => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  clearError: () => void;
  setLatestSnapshotLockVersion: (lockVersion: number) => void;
  clearIsNewWorkflow: () => void;
  setBaseWorkflow: (workflow: BaseWorkflow) => void;
  setSuppressEnableTriggerWarning: (suppress: boolean) => void;
  markEnableTriggerWarningSuppressed: () => Promise<void>;
  getLimits: (
    actionType: 'new_run' | 'activate_workflow' | 'github_sync'
  ) => Promise<void>;
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
