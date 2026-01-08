/**
 * useUnsavedChanges Hook Tests
 *
 * Tests for detecting unsaved changes by comparing the workflow state
 * from SessionContext (server snapshot) with WorkflowStore (local edits).
 */

import { renderHook, waitFor } from '@testing-library/react';
import type React from 'react';
import { beforeEach, describe, expect, test } from 'vitest';
import * as Y from 'yjs';

import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { useUnsavedChanges } from '../../../js/collaborative-editor/hooks/useUnsavedChanges';
import type { SessionContextStoreInstance } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import type { WorkflowStoreInstance } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import {
  createEmptyWorkflowYDoc,
  createMinimalWorkflowYDoc,
  setupWorkflowStoreTest,
} from '../__helpers__';
import { createSessionContext } from '../__helpers__/sessionContextFactory';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../mocks/phoenixChannel';

function createWrapper(
  sessionContextStore: SessionContextStoreInstance,
  workflowStore: WorkflowStoreInstance
): React.ComponentType<{ children: React.ReactNode }> {
  const mockStoreValue: StoreContextValue = {
    sessionContextStore,
    workflowStore,
    adaptorStore: {} as any,
    credentialStore: {} as any,
    awarenessStore: {} as any,
  };

  return ({ children }: { children: React.ReactNode }) => (
    <StoreContext.Provider value={mockStoreValue}>
      {children}
    </StoreContext.Provider>
  );
}

describe('useUnsavedChanges - Basic Detection', () => {
  let sessionContextStore: SessionContextStoreInstance;

  beforeEach(() => {
    sessionContextStore = createSessionContextStore();
  });

  test('returns false when no workflow loaded', () => {
    const { store, ydoc, cleanup } = setupWorkflowStoreTest(
      createEmptyWorkflowYDoc()
    );

    const { result } = renderHook(() => useUnsavedChanges(), {
      wrapper: createWrapper(sessionContextStore, store),
    });

    expect(result.current.hasChanges).toBe(false);

    cleanup();
  });

  test('returns false when workflow matches saved state', async () => {
    const { store, ydoc, cleanup } = setupWorkflowStoreTest(
      createEmptyWorkflowYDoc()
    );

    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);

    const jobId = '770e8400-e29b-41d4-a716-446655440000';

    // Set up workflow in Y.Doc with matching data
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('name', 'Test Workflow');

    const jobsArray = ydoc.getArray('jobs');
    const jobMap = new Y.Map();
    jobMap.set('id', jobId);
    jobMap.set('name', 'Job 1');
    jobMap.set('body', 'fn(state => state)');
    jobMap.set('adaptor', '@openfn/language-common@latest');
    jobMap.set('project_credential_id', null);
    jobMap.set('keychain_credential_id', null);
    jobsArray.push([jobMap]);

    // Set up matching session context
    mockChannel.push = (_event: string, _payload: unknown) => {
      return {
        receive: (status: string, callback: (response?: unknown) => void) => {
          if (status === 'ok') {
            setTimeout(() => {
              callback(
                createSessionContext({
                  workflow: {
                    name: 'Test Workflow',
                    jobs: [
                      {
                        id: jobId,
                        name: 'Job 1',
                        body: 'fn(state => state)',
                        adaptor: '@openfn/language-common@latest',
                        project_credential_id: null,
                        keychain_credential_id: null,
                      },
                    ],
                    triggers: [],
                    edges: [],
                    positions: {},
                  },
                })
              );
            }, 0);
          }
          return {
            receive: () => ({
              receive: () => ({ receive: () => ({}) }),
            }),
          };
        },
      };
    };

    sessionContextStore._connectChannel(mockProvider);

    const { result } = renderHook(() => useUnsavedChanges(), {
      wrapper: createWrapper(sessionContextStore, store),
    });

    await waitFor(() => {
      expect(result.current.hasChanges).toBe(false);
    });

    cleanup();
  });

  test('detects changes when job body changes', async () => {
    const { store, ydoc, cleanup } = setupWorkflowStoreTest(
      createEmptyWorkflowYDoc()
    );

    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);

    const jobId = '770e8400-e29b-41d4-a716-446655440000';

    // Set up initial workflow in session context
    mockChannel.push = (_event: string, _payload: unknown) => {
      return {
        receive: (status: string, callback: (response?: unknown) => void) => {
          if (status === 'ok') {
            setTimeout(() => {
              callback(
                createSessionContext({
                  workflow: {
                    name: 'Test Workflow',
                    jobs: [
                      {
                        id: jobId,
                        name: 'Job 1',
                        body: 'fn(state => state)',
                        adaptor: '@openfn/language-common@latest',
                        project_credential_id: null,
                        keychain_credential_id: null,
                      },
                    ],
                    triggers: [],
                    edges: [],
                    positions: {},
                  },
                })
              );
            }, 0);
          }
          return {
            receive: () => ({ receive: () => ({ receive: () => ({}) }) }),
          };
        },
      };
    };

    sessionContextStore._connectChannel(mockProvider);

    await waitFor(() => sessionContextStore.getSnapshot().workflow !== null, {
      timeout: 1000,
    });

    // Modify workflow in Y.Doc with different body
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('name', 'Test Workflow');

    const jobsArray = ydoc.getArray('jobs');
    const jobMap = new Y.Map();
    jobMap.set('id', jobId);
    jobMap.set('name', 'Job 1');
    jobMap.set(
      'body',
      'fn(state => { console.log("modified"); return state; })'
    );
    jobMap.set('adaptor', '@openfn/language-common@latest');
    jobMap.set('project_credential_id', null);
    jobMap.set('keychain_credential_id', null);
    jobsArray.push([jobMap]);

    const { result } = renderHook(() => useUnsavedChanges(), {
      wrapper: createWrapper(sessionContextStore, store),
    });

    await waitFor(() => {
      expect(result.current.hasChanges).toBe(true);
    });

    cleanup();
  });

  test('detects changes when workflow name changes', async () => {
    const { store, ydoc, cleanup } = setupWorkflowStoreTest(
      createEmptyWorkflowYDoc()
    );

    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);

    mockChannel.push = (_event: string, _payload: unknown) => {
      return {
        receive: (status: string, callback: (response?: unknown) => void) => {
          if (status === 'ok') {
            setTimeout(() => {
              callback(
                createSessionContext({
                  workflow: {
                    name: 'Original Name',
                    jobs: [],
                    triggers: [],
                    edges: [],
                    positions: {},
                  },
                })
              );
            }, 0);
          }
          return {
            receive: () => ({ receive: () => ({ receive: () => ({}) }) }),
          };
        },
      };
    };

    sessionContextStore._connectChannel(mockProvider);

    await waitFor(() => sessionContextStore.getSnapshot().workflow !== null, {
      timeout: 1000,
    });

    // Change name in Y.Doc
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('name', 'Modified Name');

    const { result } = renderHook(() => useUnsavedChanges(), {
      wrapper: createWrapper(sessionContextStore, store),
    });

    await waitFor(() => {
      expect(result.current.hasChanges).toBe(true);
    });

    cleanup();
  });
});

describe('useUnsavedChanges - Edge Cases', () => {
  let sessionContextStore: SessionContextStoreInstance;

  beforeEach(() => {
    sessionContextStore = createSessionContextStore();
  });

  test('handles null and undefined values correctly', async () => {
    const { store, ydoc, cleanup } = setupWorkflowStoreTest(
      createMinimalWorkflowYDoc()
    );
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);

    const jobId = '770e8400-e29b-41d4-a716-446655440000';

    mockChannel.push = (_event: string, _payload: unknown) => {
      return {
        receive: (status: string, callback: (response?: unknown) => void) => {
          if (status === 'ok') {
            setTimeout(() => {
              callback(
                createSessionContext({
                  workflow: {
                    name: 'Test',
                    jobs: [
                      {
                        id: jobId,
                        name: 'Job 1',
                        body: '',
                        adaptor: '@openfn/language-common@latest',
                        project_credential_id: null,
                        keychain_credential_id: null,
                      },
                    ],
                    triggers: [],
                    edges: [],
                    positions: {},
                  },
                })
              );
            }, 0);
          }
          return {
            receive: () => ({ receive: () => ({ receive: () => ({}) }) }),
          };
        },
      };
    };

    sessionContextStore._connectChannel(mockProvider);

    await waitFor(() => sessionContextStore.getSnapshot().workflow !== null, {
      timeout: 1000,
    });

    // Set up Y.Doc with matching undefined/null credential values
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('name', 'Test');

    const jobsArray = ydoc.getArray('jobs');
    const jobMap = new Y.Map();
    jobMap.set('id', jobId);
    jobMap.set('name', 'Job 1');
    jobMap.set('body', '');
    jobMap.set('adaptor', '@openfn/language-common@latest');
    jobMap.set('project_credential_id', null);
    jobMap.set('keychain_credential_id', null);
    jobsArray.push([jobMap]);
    const { result } = renderHook(() => useUnsavedChanges(), {
      wrapper: createWrapper(sessionContextStore, store),
    });

    await waitFor(() => {
      expect(result.current.hasChanges).toBe(false);
    });

    cleanup();
  });

  test('detects changes when job is added', async () => {
    const { store, ydoc, cleanup } = setupWorkflowStoreTest(
      createEmptyWorkflowYDoc()
    );

    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);

    mockChannel.push = (_event: string, _payload: unknown) => {
      return {
        receive: (status: string, callback: (response?: unknown) => void) => {
          if (status === 'ok') {
            setTimeout(() => {
              callback(
                createSessionContext({
                  workflow: {
                    name: 'Test',
                    jobs: [],
                    triggers: [],
                    edges: [],
                    positions: {},
                  },
                })
              );
            }, 0);
          }
          return {
            receive: () => ({ receive: () => ({ receive: () => ({}) }) }),
          };
        },
      };
    };

    sessionContextStore._connectChannel(mockProvider);

    await waitFor(() => sessionContextStore.getSnapshot().workflow !== null, {
      timeout: 1000,
    });

    // Add job to Y.Doc
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('name', 'Test');

    const jobsArray = ydoc.getArray('jobs');
    const jobMap = new Y.Map();
    jobMap.set('id', '770e8400-e29b-41d4-a716-446655440000');
    jobMap.set('name', 'New Job');
    jobMap.set('body', 'fn(state => state)');
    jobMap.set('adaptor', '@openfn/language-common@latest');
    jobMap.set('project_credential_id', null);
    jobMap.set('keychain_credential_id', null);
    jobsArray.push([jobMap]);

    const { result } = renderHook(() => useUnsavedChanges(), {
      wrapper: createWrapper(sessionContextStore, store),
    });

    await waitFor(() => {
      expect(result.current.hasChanges).toBe(true);
    });

    cleanup();
  });
});
