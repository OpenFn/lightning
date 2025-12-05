/**
 * useSessionContext Hooks Tests
 *
 * Tests for hooks that provide access to user, project, and app configuration
 * data from the session context store.
 */

import { act, renderHook, waitFor } from '@testing-library/react';
import type React from 'react';
import { beforeEach, describe, expect, test } from 'vitest';

import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import {
  useAppConfig,
  useProject,
  useSessionContextError,
  useSessionContextLoading,
  useUser,
} from '../../../js/collaborative-editor/hooks/useSessionContext';
import type { SessionContextStoreInstance } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import type {
  AppConfig,
  ProjectContext,
  UserContext,
} from '../../../js/collaborative-editor/types/sessionContext';
import { mockPermissions } from '../__helpers__/sessionContextFactory';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../mocks/phoenixChannel';

function createWrapper(
  sessionContextStore: SessionContextStoreInstance
): React.ComponentType<{ children: React.ReactNode }> {
  const mockStoreValue: StoreContextValue = {
    sessionContextStore,
    adaptorStore: {} as any,
    credentialStore: {} as any,
    awarenessStore: {} as any,
    workflowStore: {} as any,
  };

  return ({ children }: { children: React.ReactNode }) => (
    <StoreContext.Provider value={mockStoreValue}>
      {children}
    </StoreContext.Provider>
  );
}

function createMockUser(): UserContext {
  return {
    id: '00000000-0000-4000-8000-000000000001',
    first_name: 'Test',
    last_name: 'User',
    email: 'test@example.com',
    email_confirmed: true,
    support_user: false,
    inserted_at: new Date().toISOString(),
  };
}

function createMockProject(): ProjectContext {
  return {
    id: '00000000-0000-4000-8000-000000000002',
    name: 'Test Project',
  };
}

function createMockAppConfig(): AppConfig {
  return {
    require_email_verification: false,
  };
}

function setupHookTest(store: SessionContextStoreInstance) {
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);
  store._connectChannel(mockProvider as any);
  return { mockChannel, mockProvider };
}

describe('useSessionContext Hooks - Context Validation', () => {
  test('all hooks throw error when used outside StoreProvider', () => {
    const expectedError =
      'useSessionContextStore must be used within a StoreProvider';

    expect(() => renderHook(() => useUser())).toThrow(expectedError);
    expect(() => renderHook(() => useProject())).toThrow(expectedError);
    expect(() => renderHook(() => useAppConfig())).toThrow(expectedError);
    expect(() => renderHook(() => useSessionContextLoading())).toThrow(
      expectedError
    );
    expect(() => renderHook(() => useSessionContextError())).toThrow(
      expectedError
    );
  });
});

describe('useUser()', () => {
  let store: SessionContextStoreInstance;
  beforeEach(() => {
    store = createSessionContextStore();
  });

  test('manages user data lifecycle', async () => {
    const { mockChannel } = setupHookTest(store);
    const { result } = renderHook(() => useUser(), {
      wrapper: createWrapper(store),
    });

    expect(result.current).toBe(null);

    const mockUser = createMockUser();
    act(() => {
      (mockChannel as any)._test.emit('session_context', {
        user: mockUser,
        project: null,
        config: createMockAppConfig(),
        permissions: mockPermissions,
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
        has_read_ai_disclaimer: true,
      });
    });

    await waitFor(() => expect(result.current).toEqual(mockUser));

    const updatedUser = { ...mockUser, first_name: 'Updated' };
    act(() => {
      (mockChannel as any)._test.emit('session_context_updated', {
        user: updatedUser,
        project: null,
        config: createMockAppConfig(),
        permissions: mockPermissions,
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
        has_read_ai_disclaimer: true,
      });
    });

    await waitFor(() => {
      expect(result.current?.first_name).toBe('Updated');
    });
  });
});

describe('useProject()', () => {
  let store: SessionContextStoreInstance;
  beforeEach(() => {
    store = createSessionContextStore();
  });

  test('manages project data lifecycle', async () => {
    const { mockChannel } = setupHookTest(store);
    const { result } = renderHook(() => useProject(), {
      wrapper: createWrapper(store),
    });

    expect(result.current).toBe(null);

    const mockProject = createMockProject();
    act(() => {
      (mockChannel as any)._test.emit('session_context', {
        user: null,
        project: mockProject,
        config: createMockAppConfig(),
        permissions: mockPermissions,
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
        has_read_ai_disclaimer: true,
      });
    });

    await waitFor(() => expect(result.current).toEqual(mockProject));

    const updatedProject = { ...mockProject, name: 'Updated Project' };
    act(() => {
      (mockChannel as any)._test.emit('session_context_updated', {
        user: null,
        project: updatedProject,
        config: createMockAppConfig(),
        permissions: mockPermissions,
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
        has_read_ai_disclaimer: true,
      });
    });

    await waitFor(() => {
      expect(result.current?.name).toBe('Updated Project');
    });
  });
});

describe('useAppConfig()', () => {
  let store: SessionContextStoreInstance;
  beforeEach(() => {
    store = createSessionContextStore();
  });

  test('manages app config data lifecycle', async () => {
    const { mockChannel } = setupHookTest(store);
    const { result } = renderHook(() => useAppConfig(), {
      wrapper: createWrapper(store),
    });

    expect(result.current).toBe(null);

    const mockConfig = createMockAppConfig();
    act(() => {
      (mockChannel as any)._test.emit('session_context', {
        user: null,
        project: null,
        config: mockConfig,
        permissions: mockPermissions,
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
        has_read_ai_disclaimer: true,
      });
    });

    await waitFor(() => expect(result.current).toEqual(mockConfig));

    const updatedConfig = { ...mockConfig, require_email_verification: true };
    act(() => {
      (mockChannel as any)._test.emit('session_context_updated', {
        user: null,
        project: null,
        config: updatedConfig,
        permissions: mockPermissions,
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
        has_read_ai_disclaimer: true,
      });
    });

    await waitFor(() => {
      expect(result.current?.require_email_verification).toBe(true);
    });
  });
});

describe('useSessionContextLoading()', () => {
  let store: SessionContextStoreInstance;
  beforeEach(() => {
    store = createSessionContextStore();
  });

  test('manages loading state lifecycle', () => {
    const { result } = renderHook(() => useSessionContextLoading(), {
      wrapper: createWrapper(store),
    });

    expect(result.current).toBe(false);
    act(() => store.setLoading(true));
    expect(result.current).toBe(true);
    act(() => store.setLoading(false));
    expect(result.current).toBe(false);
  });
});

describe('useSessionContextError()', () => {
  let store: SessionContextStoreInstance;
  beforeEach(() => {
    store = createSessionContextStore();
  });

  test('manages error state lifecycle', () => {
    const { result } = renderHook(() => useSessionContextError(), {
      wrapper: createWrapper(store),
    });

    expect(result.current).toBe(null);
    act(() => store.setError('Test error'));
    expect(result.current).toBe('Test error');
    act(() => store.setError('Another error'));
    expect(result.current).toBe('Another error');
    act(() => store.clearError());
    expect(result.current).toBe(null);
  });
});

describe('Hook Integration', () => {
  let store: SessionContextStoreInstance;
  beforeEach(() => {
    store = createSessionContextStore();
  });

  test('session_context event updates all data hooks simultaneously', async () => {
    const { mockChannel } = setupHookTest(store);

    const { result: userResult } = renderHook(() => useUser(), {
      wrapper: createWrapper(store),
    });
    const { result: projectResult } = renderHook(() => useProject(), {
      wrapper: createWrapper(store),
    });
    const { result: configResult } = renderHook(() => useAppConfig(), {
      wrapper: createWrapper(store),
    });

    expect(userResult.current).toBe(null);
    expect(projectResult.current).toBe(null);
    expect(configResult.current).toBe(null);

    const mockUser = createMockUser();
    const mockProject = createMockProject();
    const mockConfig = createMockAppConfig();

    act(() => {
      (mockChannel as any)._test.emit('session_context', {
        user: mockUser,
        project: mockProject,
        config: mockConfig,
        permissions: mockPermissions,
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
        has_read_ai_disclaimer: true,
      });
    });

    await waitFor(() => {
      expect(userResult.current).toEqual(mockUser);
      expect(projectResult.current).toEqual(mockProject);
      expect(configResult.current).toEqual(mockConfig);
    });
  });

  test('error state clears loading state', () => {
    const { result: loadingResult } = renderHook(
      () => useSessionContextLoading(),
      { wrapper: createWrapper(store) }
    );
    const { result: errorResult } = renderHook(() => useSessionContextError(), {
      wrapper: createWrapper(store),
    });

    act(() => store.setLoading(true));
    expect(loadingResult.current).toBe(true);
    expect(errorResult.current).toBe(null);

    act(() => store.setError('Something went wrong'));
    expect(loadingResult.current).toBe(false);
    expect(errorResult.current).toBe('Something went wrong');
  });
});
