/**
 * Test fixtures for session context data
 *
 * Provides consistent test data that matches the Zod schemas
 * for testing session context store functionality.
 */

import type {
  UserContext,
  ProjectContext,
  AppConfig,
} from "../../../js/collaborative-editor/types/sessionContext";

/**
 * Sample user context for testing
 */
export const mockUserContext: UserContext = {
  id: "550e8400-e29b-41d4-a716-446655440000",
  first_name: "Test",
  last_name: "User",
  email: "test@example.com",
  email_confirmed: true,
  inserted_at: "2024-01-15T10:30:00Z",
};

/**
 * Sample project context for testing
 */
export const mockProjectContext: ProjectContext = {
  id: "660e8400-e29b-41d4-a716-446655440000",
  name: "Test Project",
};

/**
 * Sample app config for testing
 */
export const mockAppConfig: AppConfig = {
  require_email_verification: false,
};

/**
 * Complete session context response for testing
 */
export const mockSessionContextResponse = {
  user: mockUserContext,
  project: mockProjectContext,
  config: mockAppConfig,
};

/**
 * Session context with null user (unauthenticated state)
 */
export const mockUnauthenticatedSessionContext = {
  user: null,
  project: null,
  config: mockAppConfig,
};

/**
 * Alternative user for testing updates
 */
export const mockAlternativeUserContext: UserContext = {
  id: "770e8400-e29b-41d4-a716-446655440000",
  first_name: "Jane",
  last_name: "Smith",
  email: "jane@example.com",
  email_confirmed: false,
  inserted_at: "2024-01-20T15:45:00Z",
};

/**
 * Alternative project for testing updates
 */
export const mockAlternativeProjectContext: ProjectContext = {
  id: "880e8400-e29b-41d4-a716-446655440000",
  name: "Another Project",
};

/**
 * Updated session context for testing real-time updates
 */
export const mockUpdatedSessionContext = {
  user: mockAlternativeUserContext,
  project: mockAlternativeProjectContext,
  config: { require_email_verification: true },
};

/**
 * Invalid data samples for testing validation errors
 */
export const invalidSessionContextData = {
  missingUser: {
    // user missing entirely (not null)
    project: mockProjectContext,
    config: mockAppConfig,
  },

  invalidUserId: {
    user: {
      ...mockUserContext,
      id: "not-a-uuid", // invalid UUID format
    },
    project: mockProjectContext,
    config: mockAppConfig,
  },

  invalidUserEmail: {
    user: {
      ...mockUserContext,
      email: "not-an-email", // invalid email format
    },
    project: mockProjectContext,
    config: mockAppConfig,
  },

  missingConfig: {
    user: mockUserContext,
    project: mockProjectContext,
    // config missing entirely
  },

  invalidConfigType: {
    user: mockUserContext,
    project: mockProjectContext,
    config: {
      require_email_verification: "invalid", // should be boolean
    },
  },

  invalidProjectId: {
    user: mockUserContext,
    project: {
      ...mockProjectContext,
      id: 12345, // should be string UUID
    },
    config: mockAppConfig,
  },

  missingProjectName: {
    user: mockUserContext,
    project: {
      id: mockProjectContext.id,
      // name missing
    },
    config: mockAppConfig,
  },
};

/**
 * Helper to create session context with specific characteristics
 */
export function createMockSessionContext(
  overrides: {
    user?: UserContext | null;
    project?: ProjectContext | null;
    config?: AppConfig;
  } = {}
) {
  return {
    user: overrides.user !== undefined ? overrides.user : mockUserContext,
    project:
      overrides.project !== undefined ? overrides.project : mockProjectContext,
    config: overrides.config || mockAppConfig,
  };
}

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
    id: "990e8400-e29b-41d4-a716-446655440000", // Valid UUIDv4 format
    email: "test@example.com",
    first_name: "Test",
    last_name: "User",
    email_confirmed: true,
    inserted_at: "2025-01-13T10:30:00Z",
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
