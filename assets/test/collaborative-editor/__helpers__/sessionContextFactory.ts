/**
 * Session Context Test Factory
 *
 * Factory functions and fixtures for creating session context objects for testing.
 * These factories simplify the setup of test scenarios involving user sessions,
 * projects, permissions, and GitHub integrations.
 *
 * This is the single source of truth for session context test data.
 *
 * Usage:
 *   const context = createSessionContext({
 *     permissions: { can_edit_workflow: false },
 *     project_repo_connection: { repo: "org/repo", branch: "main" }
 *   });
 */

import type {
  AppConfig,
  Limits,
  Permissions,
  ProjectContext,
  ProjectRepoConnection,
  UserContext,
  WebhookAuthMethod,
  WorkflowTemplate,
} from '../../../js/collaborative-editor/types/sessionContext';

// =============================================================================
// BASE MOCK DATA (used as defaults in factories)
// =============================================================================

/**
 * Sample user context for testing
 */
export const mockUserContext: UserContext = {
  id: '550e8400-e29b-41d4-a716-446655440000',
  first_name: 'Test',
  last_name: 'User',
  email: 'test@example.com',
  email_confirmed: true,
  support_user: false,
  inserted_at: '2024-01-15T10:30:00Z',
};

/**
 * Sample project context for testing
 */
export const mockProjectContext: ProjectContext = {
  id: '660e8400-e29b-41d4-a716-446655440000',
  name: 'Test Project',
};

/**
 * Sample app config for testing
 */
export const mockAppConfig: AppConfig = {
  require_email_verification: false,
};

/**
 * Sample permissions for testing
 */
export const mockPermissions: Permissions = {
  can_edit_workflow: true,
  can_run_workflow: true,
  can_write_webhook_auth_method: true,
};

/**
 * Sample limits for testing
 */
export const mockLimits: Limits = {
  runs: { allowed: true, message: null },
};

/**
 * Sample workflow template for testing
 */
export const mockWorkflowTemplate: WorkflowTemplate = {
  id: '990e8400-e29b-41d4-a716-446655440000',
  name: 'Existing Template',
  description: 'An existing template description',
  tags: ['tag1', 'tag2'],
  workflow_id: '660e8400-e29b-41d4-a716-446655440000',
  code: 'name: Test Workflow\njobs:\n  test-job:\n    adaptor: "@openfn/language-common@latest"',
  positions: { 'job-1': { x: 100, y: 100 } },
};

/**
 * Alternative user for testing updates
 */
export const mockAlternativeUserContext: UserContext = {
  id: '770e8400-e29b-41d4-a716-446655440000',
  first_name: 'Jane',
  last_name: 'Smith',
  email: 'jane@example.com',
  email_confirmed: false,
  support_user: false,
  inserted_at: '2024-01-20T15:45:00Z',
};

/**
 * Alternative project for testing updates
 */
export const mockAlternativeProjectContext: ProjectContext = {
  id: '880e8400-e29b-41d4-a716-446655440000',
  name: 'Another Project',
};

// =============================================================================
// COMPLETE SESSION CONTEXT FIXTURES
// =============================================================================

/**
 * Session context response type matching backend format
 */
export interface SessionContextResponse {
  user: UserContext | null;
  project: ProjectContext | null;
  config: AppConfig;
  permissions: Permissions;
  latest_snapshot_lock_version: number;
  project_repo_connection: ProjectRepoConnection | null;
  webhook_auth_methods: WebhookAuthMethod[];
  workflow_template: any | null;
  has_read_ai_disclaimer: boolean;
  limits?: Limits;
}

/**
 * Complete session context response for testing
 * (limits omitted - defaults to allowed)
 */
export const mockSessionContextResponse: SessionContextResponse = {
  user: mockUserContext,
  project: mockProjectContext,
  config: mockAppConfig,
  permissions: mockPermissions,
  latest_snapshot_lock_version: 1,
  project_repo_connection: null,
  webhook_auth_methods: [],
  workflow_template: null,
  has_read_ai_disclaimer: true,
};

/**
 * Session context with null user (unauthenticated state)
 * (limits omitted - defaults to allowed)
 */
export const mockUnauthenticatedSessionContext: SessionContextResponse = {
  user: null,
  project: null,
  config: mockAppConfig,
  permissions: mockPermissions,
  latest_snapshot_lock_version: 1,
  project_repo_connection: null,
  webhook_auth_methods: [],
  workflow_template: null,
  has_read_ai_disclaimer: false,
};

/**
 * Updated session context for testing real-time updates
 * (limits omitted - defaults to allowed)
 */
export const mockUpdatedSessionContext: SessionContextResponse = {
  user: mockAlternativeUserContext,
  project: mockAlternativeProjectContext,
  config: { require_email_verification: true },
  permissions: mockPermissions,
  latest_snapshot_lock_version: 2,
  project_repo_connection: null,
  webhook_auth_methods: [],
  workflow_template: null,
  has_read_ai_disclaimer: true,
};

// =============================================================================
// INVALID DATA FIXTURES (for validation error testing)
// =============================================================================

/**
 * Invalid data samples for testing validation errors
 */
export const invalidSessionContextData = {
  missingUser: {
    // user missing entirely (not null)
    project: mockProjectContext,
    config: mockAppConfig,
    permissions: mockPermissions,
    latest_snapshot_lock_version: 1,
    project_repo_connection: null,
    webhook_auth_methods: [],
  },

  invalidUserId: {
    user: {
      ...mockUserContext,
      id: 'not-a-uuid', // invalid UUID format
    },
    project: mockProjectContext,
    config: mockAppConfig,
    permissions: mockPermissions,
    latest_snapshot_lock_version: 1,
    project_repo_connection: null,
    webhook_auth_methods: [],
  },

  invalidUserEmail: {
    user: {
      ...mockUserContext,
      email: 'not-an-email', // invalid email format
    },
    project: mockProjectContext,
    config: mockAppConfig,
    permissions: mockPermissions,
    latest_snapshot_lock_version: 1,
    project_repo_connection: null,
    webhook_auth_methods: [],
  },

  missingConfig: {
    user: mockUserContext,
    project: mockProjectContext,
    // config missing entirely
    permissions: mockPermissions,
    latest_snapshot_lock_version: 1,
    project_repo_connection: null,
    webhook_auth_methods: [],
  },

  invalidConfigType: {
    user: mockUserContext,
    project: mockProjectContext,
    config: {
      require_email_verification: 'invalid', // should be boolean
    },
    permissions: mockPermissions,
    latest_snapshot_lock_version: 1,
    project_repo_connection: null,
    webhook_auth_methods: [],
  },

  invalidProjectId: {
    user: mockUserContext,
    project: {
      ...mockProjectContext,
      id: 12345, // should be string UUID
    },
    config: mockAppConfig,
    permissions: mockPermissions,
    latest_snapshot_lock_version: 1,
    project_repo_connection: null,
    webhook_auth_methods: [],
  },

  missingProjectName: {
    user: mockUserContext,
    project: {
      id: mockProjectContext.id,
      // name missing
    },
    config: mockAppConfig,
    permissions: mockPermissions,
    latest_snapshot_lock_version: 1,
    project_repo_connection: null,
    webhook_auth_methods: [],
  },
};

// =============================================================================
// FACTORY FUNCTIONS
// =============================================================================

/**
 * Input for creating a session context with factory functions.
 * All fields are optional and can be partially specified.
 */
export interface CreateSessionContextOptions {
  user?: Partial<UserContext> | null;
  project?: Partial<ProjectContext> | null;
  config?: Partial<AppConfig>;
  permissions?: Partial<Permissions>;
  latest_snapshot_lock_version?: number;
  project_repo_connection?: Partial<ProjectRepoConnection> | null;
  webhook_auth_methods?: WebhookAuthMethod[];
  workflow_template?: WorkflowTemplate | null;
  has_read_ai_disclaimer?: boolean;
  limits?: Partial<Limits>;
}

/**
 * Creates a complete session context response for testing
 *
 * This helper creates a properly structured session context object matching
 * the backend response format. All fields have sensible defaults and can be
 * partially overridden.
 *
 * @param options - Configuration object to override defaults
 * @returns Complete SessionContextResponse object
 *
 * @example
 * // Minimal usage - all defaults (authenticated user with edit permissions)
 * const context = createSessionContext();
 *
 * @example
 * // Override specific fields
 * const context = createSessionContext({
 *   permissions: { can_edit_workflow: false },
 *   project_repo_connection: { repo: "openfn/demo" }
 * });
 *
 * @example
 * // Unauthenticated user
 * const context = createSessionContext({ user: null, project: null });
 *
 * @example
 * // Partial user override
 * const context = createSessionContext({
 *   user: { email_confirmed: false }
 * });
 */
export function createSessionContext(
  options: CreateSessionContextOptions = {}
): SessionContextResponse {
  // Handle user field - null if explicitly set to null, otherwise merge with defaults
  const user: UserContext | null =
    options.user === null
      ? null
      : {
          id: '550e8400-e29b-41d4-a716-446655440000',
          first_name: 'Test',
          last_name: 'User',
          email: 'test@example.com',
          email_confirmed: true,
          support_user: false,
          inserted_at: '2025-01-13T10:30:00Z',
          ...options.user,
        };

  // Handle project field - null if explicitly set to null, otherwise merge with defaults
  const project: ProjectContext | null =
    options.project === null
      ? null
      : {
          id: '660e8400-e29b-41d4-a716-446655440000',
          name: 'Test Project',
          ...options.project,
        };

  // Handle config - always present, merge with defaults
  const config: AppConfig = {
    require_email_verification: false,
    ...options.config,
  };

  // Handle permissions - always present, merge with defaults
  const permissions: Permissions = {
    can_edit_workflow: true,
    can_run_workflow: true,
    can_write_webhook_auth_method: true,
    ...options.permissions,
  };

  // Handle limits - optional, only include if explicitly provided
  const limits: Limits | undefined = options.limits
    ? {
        runs: { allowed: true, message: null },
        ...options.limits,
      }
    : undefined;

  // Handle project_repo_connection - null by default, merge if provided
  let project_repo_connection: ProjectRepoConnection | null = null;
  if (
    options.project_repo_connection !== undefined &&
    options.project_repo_connection !== null
  ) {
    project_repo_connection = {
      id: '770e8400-e29b-41d4-a716-446655440000',
      repo: 'openfn/demo',
      branch: 'main',
      github_installation_id: '12345678',
      ...options.project_repo_connection,
    };
  }

  const response: any = {
    user,
    project,
    config,
    permissions,
    latest_snapshot_lock_version: options.latest_snapshot_lock_version ?? 1,
    project_repo_connection,
    webhook_auth_methods: options.webhook_auth_methods ?? [],
    workflow_template: options.workflow_template ?? null,
    has_read_ai_disclaimer: options.has_read_ai_disclaimer ?? true,
  };

  // Only add limits if provided
  if (limits !== undefined) {
    response.limits = limits;
  }

  return response;
}

/**
 * Creates a session context for an unauthenticated user
 *
 * @returns SessionContextResponse with null user and project
 *
 * @example
 * const context = createUnauthenticatedContext();
 * expect(context.user).toBe(null);
 * expect(context.project).toBe(null);
 */
export function createUnauthenticatedContext(): SessionContextResponse {
  return createSessionContext({ user: null, project: null });
}

/**
 * Creates a session context with GitHub repository connection
 *
 * @param repo - Repository name in "owner/repo" format
 * @param branch - Branch name
 * @returns SessionContextResponse with GitHub connection configured
 *
 * @example
 * const context = createGithubConnectedContext("openfn/workflows", "develop");
 * expect(context.project_repo_connection?.repo).toBe("openfn/workflows");
 * expect(context.project_repo_connection?.branch).toBe("develop");
 */
export function createGithubConnectedContext(
  repo = 'openfn/demo',
  branch = 'main'
): SessionContextResponse {
  return createSessionContext({
    project_repo_connection: { repo, branch },
  });
}

/**
 * Creates a session context for a read-only user (no edit permissions)
 *
 * @returns SessionContextResponse with can_edit_workflow set to false
 *
 * @example
 * const context = createReadOnlyContext();
 * expect(context.permissions.can_edit_workflow).toBe(false);
 */
export function createReadOnlyContext(): SessionContextResponse {
  return createSessionContext({
    permissions: { can_edit_workflow: false, can_run_workflow: false },
  });
}

/**
 * Creates a session context with email verification required
 *
 * @param emailConfirmed - Whether the user's email is confirmed
 * @returns SessionContextResponse with email verification config and optional unconfirmed user
 *
 * @example
 * const context = createEmailVerificationContext(false);
 * expect(context.config.require_email_verification).toBe(true);
 * expect(context.user?.email_confirmed).toBe(false);
 */
export function createEmailVerificationContext(
  emailConfirmed = false
): SessionContextResponse {
  return createSessionContext({
    config: { require_email_verification: true },
    user: { email_confirmed: emailConfirmed },
  });
}

/**
 * Creates a session context for a new workflow (lock version 0)
 *
 * @returns SessionContextResponse with latest_snapshot_lock_version set to 0
 *
 * @example
 * const context = createNewWorkflowContext();
 * expect(context.latest_snapshot_lock_version).toBe(0);
 */
export function createNewWorkflowContext(): SessionContextResponse {
  return createSessionContext({
    latest_snapshot_lock_version: 0,
  });
}

// =============================================================================
// INDIVIDUAL COMPONENT FACTORIES
// =============================================================================

/**
 * Helper to create a mock UserContext with custom properties
 *
 * Creates a user context object with sensible defaults that can be
 * overridden for specific test scenarios.
 *
 * @param overrides - Partial UserContext to override defaults
 * @returns Complete UserContext object
 *
 * @example
 * const user = createMockUser({ email_confirmed: false });
 * expect(user.email_confirmed).toBe(false);
 */
export function createMockUser(
  overrides: Partial<UserContext> = {}
): UserContext {
  return {
    id: '990e8400-e29b-41d4-a716-446655440000', // Valid UUIDv4 format
    email: 'test@example.com',
    first_name: 'Test',
    last_name: 'User',
    email_confirmed: true,
    support_user: false,
    inserted_at: '2025-01-13T10:30:00Z',
    ...overrides,
  };
}

/**
 * Helper to create a mock AppConfig with custom properties
 *
 * Creates an app config object with sensible defaults that can be
 * overridden for specific test scenarios.
 *
 * @param overrides - Partial AppConfig to override defaults
 * @returns Complete AppConfig object
 *
 * @example
 * const config = createMockConfig({ require_email_verification: true });
 * expect(config.require_email_verification).toBe(true);
 */
export function createMockConfig(
  overrides: Partial<AppConfig> = {}
): AppConfig {
  return {
    require_email_verification: false,
    ...overrides,
  };
}

/**
 * Helper to create a mock ProjectContext with custom properties
 *
 * @param overrides - Partial ProjectContext to override defaults
 * @returns Complete ProjectContext object
 *
 * @example
 * const project = createMockProject({ name: "My Project" });
 * expect(project.name).toBe("My Project");
 */
export function createMockProject(
  overrides: Partial<ProjectContext> = {}
): ProjectContext {
  return {
    id: '660e8400-e29b-41d4-a716-446655440000',
    name: 'Test Project',
    ...overrides,
  };
}

/**
 * Helper to create a mock WorkflowTemplate with custom properties
 *
 * Creates a workflow template object with sensible defaults that can be
 * overridden for specific test scenarios.
 *
 * @param overrides - Partial WorkflowTemplate to override defaults
 * @returns Complete WorkflowTemplate object
 *
 * @example
 * const template = createMockWorkflowTemplate({ name: "My Template" });
 * expect(template.name).toBe("My Template");
 *
 * @example
 * // Use with session context
 * const context = createSessionContext({
 *   workflow_template: createMockWorkflowTemplate({ name: "Test Template" })
 * });
 */
export function createMockWorkflowTemplate(
  overrides: Partial<WorkflowTemplate> = {}
): WorkflowTemplate {
  return {
    ...mockWorkflowTemplate,
    ...overrides,
  };
}

/**
 * Helper to create session context with specific characteristics
 * (Alias for createSessionContext for backward compatibility)
 *
 * @deprecated Use createSessionContext instead
 */
export function createMockSessionContext(
  overrides: CreateSessionContextOptions = {}
): SessionContextResponse {
  return createSessionContext(overrides);
}
