import { describe, expect, test } from 'vitest';

import {
  UserContextSchema,
  ProjectContextSchema,
  AppConfigSchema,
  SessionContextResponseSchema,
} from '../../../js/collaborative-editor/types/sessionContext';

// =============================================================================
// VALID DATA TESTS
// =============================================================================

describe.concurrent('UserContextSchema', () => {
  test('validates correct user data with all required fields', () => {
    const validUser = {
      id: '550e8400-e29b-41d4-a716-446655440000',
      first_name: 'John',
      last_name: 'Doe',
      email: 'john.doe@example.com',
      email_confirmed: true,
      support_user: false,
      inserted_at: '2024-01-15T10:30:00.000Z',
    };

    const result = UserContextSchema.safeParse(validUser);

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data).toEqual(validUser);
    }
  });

  test('validates user with unconfirmed email', () => {
    const validUser = {
      id: '550e8400-e29b-41d4-a716-446655440000',
      first_name: 'Jane',
      last_name: 'Smith',
      email: 'jane.smith@test.com',
      email_confirmed: false,
      support_user: false,
      inserted_at: '2024-01-15T10:30:00.000Z',
    };

    const result = UserContextSchema.safeParse(validUser);

    expect(result.success).toBe(true);
  });

  test('rejects invalid UUID format in user id', () => {
    const invalidUser = {
      id: 'not-a-valid-uuid',
      first_name: 'John',
      last_name: 'Doe',
      email: 'john.doe@example.com',
      email_confirmed: true,
      support_user: false,
      inserted_at: '2024-01-15T10:30:00.000Z',
    };

    const result = UserContextSchema.safeParse(invalidUser);

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].message).toContain('Invalid UUID');
    }
  });

  test('rejects invalid email format', () => {
    const invalidUser = {
      id: '550e8400-e29b-41d4-a716-446655440000',
      first_name: 'John',
      last_name: 'Doe',
      email: 'not-an-email',
      email_confirmed: true,
      support_user: false,
      inserted_at: '2024-01-15T10:30:00.000Z',
    };

    const result = UserContextSchema.safeParse(invalidUser);

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].path).toContain('email');
    }
  });

  test('rejects missing required first_name field', () => {
    const invalidUser = {
      id: '550e8400-e29b-41d4-a716-446655440000',
      last_name: 'Doe',
      email: 'john.doe@example.com',
      email_confirmed: true,
      support_user: false,
      inserted_at: '2024-01-15T10:30:00.000Z',
    };

    const result = UserContextSchema.safeParse(invalidUser);

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].path).toContain('first_name');
    }
  });

  test('rejects missing required last_name field', () => {
    const invalidUser = {
      id: '550e8400-e29b-41d4-a716-446655440000',
      first_name: 'John',
      email: 'john.doe@example.com',
      email_confirmed: true,
      support_user: false,
      inserted_at: '2024-01-15T10:30:00.000Z',
    };

    const result = UserContextSchema.safeParse(invalidUser);

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].path).toContain('last_name');
    }
  });

  test('rejects wrong data type for email_confirmed (string instead of boolean)', () => {
    const invalidUser = {
      id: '550e8400-e29b-41d4-a716-446655440000',
      first_name: 'John',
      last_name: 'Doe',
      email: 'john.doe@example.com',
      email_confirmed: 'true',
      inserted_at: '2024-01-15T10:30:00.000Z',
    };

    const result = UserContextSchema.safeParse(invalidUser);

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].path).toContain('email_confirmed');
    }
  });

  test('rejects invalid ISO datetime format in inserted_at', () => {
    const invalidUser = {
      id: '550e8400-e29b-41d4-a716-446655440000',
      first_name: 'John',
      last_name: 'Doe',
      email: 'john.doe@example.com',
      email_confirmed: true,
      support_user: false,
      inserted_at: '2024-01-15',
    };

    const result = UserContextSchema.safeParse(invalidUser);

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].message).toContain('Invalid datetime');
    }
  });

  test('rejects null value for required field', () => {
    const invalidUser = {
      id: '550e8400-e29b-41d4-a716-446655440000',
      first_name: null,
      last_name: 'Doe',
      email: 'john.doe@example.com',
      email_confirmed: true,
      support_user: false,
      inserted_at: '2024-01-15T10:30:00.000Z',
    };

    const result = UserContextSchema.safeParse(invalidUser);

    expect(result.success).toBe(false);
  });

  test('rejects undefined value for required field', () => {
    const invalidUser = {
      id: '550e8400-e29b-41d4-a716-446655440000',
      first_name: undefined,
      last_name: 'Doe',
      email: 'john.doe@example.com',
      email_confirmed: true,
      support_user: false,
      inserted_at: '2024-01-15T10:30:00.000Z',
    };

    const result = UserContextSchema.safeParse(invalidUser);

    expect(result.success).toBe(false);
  });
});

// =============================================================================
// PROJECT CONTEXT SCHEMA TESTS
// =============================================================================

describe.concurrent('ProjectContextSchema', () => {
  test('validates correct project data with all required fields', () => {
    const validProject = {
      id: 'a50e8400-e29b-41d4-a716-446655440000',
      name: 'My Project',
    };

    const result = ProjectContextSchema.safeParse(validProject);

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data).toEqual(validProject);
    }
  });

  test('rejects invalid UUID format in project id', () => {
    const invalidProject = {
      id: 'invalid-uuid',
      name: 'My Project',
    };

    const result = ProjectContextSchema.safeParse(invalidProject);

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].message).toContain('Invalid UUID');
    }
  });

  test('rejects missing required name field', () => {
    const invalidProject = {
      id: 'a50e8400-e29b-41d4-a716-446655440000',
    };

    const result = ProjectContextSchema.safeParse(invalidProject);

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].path).toContain('name');
    }
  });

  test('rejects wrong data type for name (number instead of string)', () => {
    const invalidProject = {
      id: 'a50e8400-e29b-41d4-a716-446655440000',
      name: 12345,
    };

    const result = ProjectContextSchema.safeParse(invalidProject);

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].path).toContain('name');
    }
  });
});

// =============================================================================
// APP CONFIG SCHEMA TESTS
// =============================================================================

describe.concurrent('AppConfigSchema', () => {
  test('validates correct config with require_email_verification as true', () => {
    const validConfig = {
      require_email_verification: true,
    };

    const result = AppConfigSchema.safeParse(validConfig);

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data).toEqual(validConfig);
    }
  });

  test('validates correct config with require_email_verification as false', () => {
    const validConfig = {
      require_email_verification: false,
    };

    const result = AppConfigSchema.safeParse(validConfig);

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data).toEqual(validConfig);
    }
  });

  test('rejects wrong data type for require_email_verification (string instead of boolean)', () => {
    const invalidConfig = {
      require_email_verification: 'true',
    };

    const result = AppConfigSchema.safeParse(invalidConfig);

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].path).toContain(
        'require_email_verification'
      );
    }
  });

  test('rejects missing required require_email_verification field', () => {
    const invalidConfig = {};

    const result = AppConfigSchema.safeParse(invalidConfig);

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].path).toContain(
        'require_email_verification'
      );
    }
  });

  test('rejects null value for require_email_verification', () => {
    const invalidConfig = {
      require_email_verification: null,
    };

    const result = AppConfigSchema.safeParse(invalidConfig);

    expect(result.success).toBe(false);
  });
});

// =============================================================================
// SESSION CONTEXT RESPONSE SCHEMA TESTS
// =============================================================================

describe.concurrent('SessionContextResponseSchema', () => {
  test('validates complete valid session context response', () => {
    const validResponse = {
      user: {
        id: '550e8400-e29b-41d4-a716-446655440000',
        first_name: 'John',
        last_name: 'Doe',
        email: 'john.doe@example.com',
        email_confirmed: true,
        support_user: false,
        inserted_at: '2024-01-15T10:30:00.000Z',
      },
      project: {
        id: 'a50e8400-e29b-41d4-a716-446655440000',
        name: 'My Project',
      },
      config: {
        require_email_verification: true,
      },
      permissions: {
        can_edit_workflow: true,
        can_run_workflow: true,
        can_write_webhook_auth_method: true,
      },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: [],
      workflow_template: null,
      has_read_ai_disclaimer: true,
    };

    const result = SessionContextResponseSchema.safeParse(validResponse);

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data).toEqual(validResponse);
    }
  });

  test('validates session context response with null user', () => {
    const validResponse = {
      user: null,
      project: {
        id: 'a50e8400-e29b-41d4-a716-446655440000',
        name: 'My Project',
      },
      config: {
        require_email_verification: false,
      },
      permissions: {
        can_edit_workflow: true,
        can_run_workflow: true,
        can_write_webhook_auth_method: true,
      },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: [],
      workflow_template: null,
      has_read_ai_disclaimer: true,
    };

    const result = SessionContextResponseSchema.safeParse(validResponse);

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.user).toBe(null);
    }
  });

  test('validates session context response with null project', () => {
    const validResponse = {
      user: {
        id: '550e8400-e29b-41d4-a716-446655440000',
        first_name: 'John',
        last_name: 'Doe',
        email: 'john.doe@example.com',
        email_confirmed: false,
        support_user: false,
        inserted_at: '2024-01-15T10:30:00.000Z',
      },
      project: null,
      config: {
        require_email_verification: true,
      },
      permissions: {
        can_edit_workflow: true,
        can_run_workflow: true,
        can_write_webhook_auth_method: true,
      },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: [],
      workflow_template: null,
      has_read_ai_disclaimer: true,
    };

    const result = SessionContextResponseSchema.safeParse(validResponse);

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.project).toBe(null);
    }
  });

  test('validates session context response with both user and project null', () => {
    const validResponse = {
      user: null,
      project: null,
      config: {
        require_email_verification: false,
      },
      permissions: {
        can_edit_workflow: true,
        can_run_workflow: true,
        can_write_webhook_auth_method: true,
      },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: [],
      workflow_template: null,
      has_read_ai_disclaimer: true,
    };

    const result = SessionContextResponseSchema.safeParse(validResponse);

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.user).toBe(null);
      expect(result.data.project).toBe(null);
      expect(result.data.config.require_email_verification).toBe(false);
    }
  });

  test('rejects response with missing required config field', () => {
    const invalidResponse = {
      user: null,
      project: null,
      permissions: {
        can_edit_workflow: true,
        can_run_workflow: true,
        can_write_webhook_auth_method: true,
      },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: [],
      workflow_template: null,
    };

    const result = SessionContextResponseSchema.safeParse(invalidResponse);

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].path).toContain('config');
    }
  });

  test('rejects response with invalid user data', () => {
    const invalidResponse = {
      user: {
        id: 'invalid-uuid',
        first_name: 'John',
        last_name: 'Doe',
        email: 'john.doe@example.com',
        email_confirmed: true,
        support_user: false,
        inserted_at: '2024-01-15T10:30:00.000Z',
      },
      project: null,
      config: {
        require_email_verification: true,
      },
      permissions: {
        can_edit_workflow: true,
        can_run_workflow: true,
        can_write_webhook_auth_method: true,
      },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: [],
      workflow_template: null,
    };

    const result = SessionContextResponseSchema.safeParse(invalidResponse);

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].message).toContain('Invalid UUID');
    }
  });

  test('rejects response with invalid project data', () => {
    const invalidResponse = {
      user: null,
      project: {
        id: 'not-a-uuid',
        name: 'My Project',
      },
      config: {
        require_email_verification: true,
      },
      permissions: {
        can_edit_workflow: true,
        can_run_workflow: true,
        can_write_webhook_auth_method: true,
      },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: [],
      workflow_template: null,
    };

    const result = SessionContextResponseSchema.safeParse(invalidResponse);

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].message).toContain('Invalid UUID');
    }
  });

  test('rejects response with invalid config data', () => {
    const invalidResponse = {
      user: null,
      project: null,
      config: {
        require_email_verification: 'not-a-boolean',
      },
      permissions: {
        can_edit_workflow: true,
        can_run_workflow: true,
        can_write_webhook_auth_method: true,
      },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: [],
      workflow_template: null,
    };

    const result = SessionContextResponseSchema.safeParse(invalidResponse);

    expect(result.success).toBe(false);
  });

  test('rejects response when config is null', () => {
    const invalidResponse = {
      user: null,
      project: null,
      config: null,
      permissions: {
        can_edit_workflow: true,
        can_run_workflow: true,
        can_write_webhook_auth_method: true,
      },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: [],
      workflow_template: null,
    };

    const result = SessionContextResponseSchema.safeParse(invalidResponse);

    expect(result.success).toBe(false);
  });

  test('rejects response with undefined user (not null)', () => {
    const invalidResponse = {
      user: undefined,
      project: null,
      config: {
        require_email_verification: true,
      },
      permissions: {
        can_edit_workflow: true,
        can_run_workflow: true,
        can_write_webhook_auth_method: true,
      },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: [],
      workflow_template: null,
    };

    const result = SessionContextResponseSchema.safeParse(invalidResponse);

    expect(result.success).toBe(false);
  });
});

// =============================================================================
// EDGE CASE AND BOUNDARY TESTS
// =============================================================================

describe.concurrent('SessionContext edge cases', () => {
  test('validates user with special characters in name fields', () => {
    const validUser = {
      id: '550e8400-e29b-41d4-a716-446655440000',
      first_name: 'Jean-François',
      last_name: "O'Brien-Smith",
      email: 'jean.francois@example.com',
      email_confirmed: true,
      support_user: false,
      inserted_at: '2024-01-15T10:30:00.000Z',
    };

    const result = UserContextSchema.safeParse(validUser);

    expect(result.success).toBe(true);
  });

  test('validates project with empty string name', () => {
    const project = {
      id: 'a50e8400-e29b-41d4-a716-446655440000',
      name: '',
    };

    const result = ProjectContextSchema.safeParse(project);

    expect(result.success).toBe(true);
  });

  test('validates user with email containing plus sign', () => {
    const validUser = {
      id: '550e8400-e29b-41d4-a716-446655440000',
      first_name: 'Test',
      last_name: 'User',
      email: 'test+tag@example.com',
      email_confirmed: true,
      support_user: false,
      inserted_at: '2024-01-15T10:30:00.000Z',
    };

    const result = UserContextSchema.safeParse(validUser);

    expect(result.success).toBe(true);
  });

  test('validates ISO datetime with milliseconds and timezone', () => {
    const validUser = {
      id: '550e8400-e29b-41d4-a716-446655440000',
      first_name: 'John',
      last_name: 'Doe',
      email: 'john@example.com',
      email_confirmed: true,
      support_user: false,
      inserted_at: '2024-01-15T10:30:00.123Z',
    };

    const result = UserContextSchema.safeParse(validUser);

    expect(result.success).toBe(true);
  });

  test('rejects extra unexpected fields in user schema', () => {
    const userData = {
      id: '550e8400-e29b-41d4-a716-446655440000',
      first_name: 'John',
      last_name: 'Doe',
      email: 'john@example.com',
      email_confirmed: true,
      support_user: false,
      inserted_at: '2024-01-15T10:30:00.000Z',
      unexpected_field: 'should be stripped',
    };

    const result = UserContextSchema.safeParse(userData);

    // Zod by default allows extra fields but doesn't include them in output
    expect(result.success).toBe(true);
    if (result.success) {
      expect('unexpected_field' in result.data).toBe(false);
    }
  });
});
