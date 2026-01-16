import { act, renderHook } from '@testing-library/react';
import type React from 'react';
import { beforeEach, describe, expect, test } from 'vitest';

import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { useJobDeleteValidation } from '../../../js/collaborative-editor/hooks/useJobDeleteValidation';
import type { SessionContextStoreInstance } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import type { WorkflowStoreInstance } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import { mockPermissions } from '../__helpers__/sessionContextFactory';
import { createWorkflowYDoc } from '../__helpers__/workflowFactory';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../mocks/phoenixChannel';

/**
 * Creates a React wrapper with store providers for hook testing
 */
function createWrapper(
  workflowStore: WorkflowStoreInstance,
  sessionContextStore: SessionContextStoreInstance
): React.ComponentType<{ children: React.ReactNode }> {
  const mockStoreValue: StoreContextValue = {
    workflowStore,
    sessionContextStore,
    adaptorStore: {} as any,
    credentialStore: {} as any,
    awarenessStore: {} as any,
    uiStore: {} as any,
  };

  return ({ children }: { children: React.ReactNode }) => (
    <StoreContext.Provider value={mockStoreValue}>
      {children}
    </StoreContext.Provider>
  );
}

/**
 * Helper to set permissions in session context store via channel mock
 */
function setPermissions(channelMock: any, can_edit_workflow: boolean) {
  act(() => {
    channelMock._test.emit('session_context', {
      user: null,
      project: null,
      config: {
        require_email_verification: false,
        kafka_triggers_enabled: false,
      },
      permissions: { ...mockPermissions, can_edit_workflow },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: [],
      workflow_template: null,
      has_read_ai_disclaimer: true,
    });
  });
}

/**
 * Helper to create and connect a workflow store with Y.Doc
 */
function createConnectedWorkflowStore(ydoc: any): WorkflowStoreInstance {
  const store = createWorkflowStore();
  const mockProvider = createMockPhoenixChannelProvider(
    createMockPhoenixChannel()
  );
  store.connect(ydoc, mockProvider as any);
  return store;
}

describe('useJobDeleteValidation - Permission Validation', () => {
  let workflowStore: WorkflowStoreInstance;
  let sessionContextStore: SessionContextStoreInstance;
  let channelMock: any;

  beforeEach(() => {
    const ydoc = createWorkflowYDoc({
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
      },
      edges: [],
    });

    workflowStore = createConnectedWorkflowStore(ydoc);
    sessionContextStore = createSessionContextStore();
    channelMock = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(channelMock);
    sessionContextStore._connectChannel(mockProvider as any);
  });

  test('allows deletion when user has can_edit_workflow permission', () => {
    setPermissions(channelMock, true);

    const { result } = renderHook(() => useJobDeleteValidation('job-a'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    expect(result.current.canDelete).toBe(true);
    expect(result.current.disableReason).toBe(null);
  });

  test('blocks deletion when user lacks can_edit_workflow permission', () => {
    setPermissions(channelMock, false);

    const { result } = renderHook(() => useJobDeleteValidation('job-a'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    expect(result.current.canDelete).toBe(false);
    expect(result.current.disableReason).toBe(
      "You don't have permission to edit this workflow"
    );
  });

  test('blocks deletion when permissions are null (not loaded)', () => {
    // Don't set permissions - leave them as null

    const { result } = renderHook(() => useJobDeleteValidation('job-a'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    expect(result.current.canDelete).toBe(false);
    expect(result.current.disableReason).toBe(
      "You don't have permission to edit this workflow"
    );
  });
});

describe('useJobDeleteValidation - First Job Detection', () => {
  let workflowStore: WorkflowStoreInstance;
  let sessionContextStore: SessionContextStoreInstance;
  let channelMock: any;

  beforeEach(() => {
    sessionContextStore = createSessionContextStore();
    channelMock = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(channelMock);
    sessionContextStore._connectChannel(mockProvider as any);
    setPermissions(channelMock, true);
  });

  test('blocks deletion of job with ONLY trigger parent (first job)', () => {
    const ydoc = createWorkflowYDoc({
      triggers: {
        'trigger-1': { id: 'trigger-1', type: 'webhook' },
      },
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
      },
      edges: [{ id: 'e1', source: 'trigger-1', target: 'job-a' }],
    });

    workflowStore = createConnectedWorkflowStore(ydoc);

    const { result } = renderHook(() => useJobDeleteValidation('job-a'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    expect(result.current.isFirstJob).toBe(true);
    expect(result.current.canDelete).toBe(false);
    expect(result.current.disableReason).toBe(
      "You can't delete the first step in a workflow."
    );
  });

  test('allows deletion of job with ONLY job parent (not first job)', () => {
    const ydoc = createWorkflowYDoc({
      triggers: {
        'trigger-1': { id: 'trigger-1', type: 'webhook' },
      },
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common',
        },
      },
      edges: [
        { id: 'e1', source: 'trigger-1', target: 'job-a' },
        { id: 'e2', source: 'job-a', target: 'job-b' },
      ],
    });

    workflowStore = createConnectedWorkflowStore(ydoc);

    const { result } = renderHook(() => useJobDeleteValidation('job-b'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    expect(result.current.isFirstJob).toBe(false);
    expect(result.current.canDelete).toBe(true);
    expect(result.current.disableReason).toBe(null);
  });

  test('allows deletion of job with BOTH trigger AND job parents (CRITICAL BUG FIX)', () => {
    // This is the critical bug fix scenario:
    // Job C has TWO parents: a trigger AND job-b
    // Previously this was incorrectly blocked as a "first job"
    //
    // Workflow structure:
    //   Trigger-1 → Job A → Job B
    //             ↘ Job C ↗
    const ydoc = createWorkflowYDoc({
      triggers: {
        'trigger-1': { id: 'trigger-1', type: 'webhook' },
      },
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common',
        },
        'job-c': {
          id: 'job-c',
          name: 'Job C',
          adaptor: '@openfn/language-common',
        },
      },
      edges: [
        { id: 'e1', source: 'trigger-1', target: 'job-a' },
        { id: 'e2', source: 'job-a', target: 'job-b' },
        { id: 'e3', source: 'trigger-1', target: 'job-c' },
        { id: 'e4', source: 'job-b', target: 'job-c' },
      ],
    });

    workflowStore = createConnectedWorkflowStore(ydoc);

    const { result } = renderHook(() => useJobDeleteValidation('job-c'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    // Job C has a job parent (job-b), so it should NOT be considered a first job
    expect(result.current.isFirstJob).toBe(false);
    expect(result.current.canDelete).toBe(true);
    expect(result.current.disableReason).toBe(null);
  });

  test('allows deletion of orphan job with no parents', () => {
    const ydoc = createWorkflowYDoc({
      triggers: {
        'trigger-1': { id: 'trigger-1', type: 'webhook' },
      },
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
        'job-orphan': {
          id: 'job-orphan',
          name: 'Orphan Job',
          adaptor: '@openfn/language-common',
        },
      },
      edges: [{ id: 'e1', source: 'trigger-1', target: 'job-a' }],
    });

    workflowStore = createConnectedWorkflowStore(ydoc);

    const { result } = renderHook(() => useJobDeleteValidation('job-orphan'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    expect(result.current.isFirstJob).toBe(false);
    expect(result.current.canDelete).toBe(true);
    expect(result.current.disableReason).toBe(null);
  });

  test('allows deletion of job with multiple job parents', () => {
    // Create diamond pattern: Job A and Job B both feed into Job C
    // Trigger → Job A → Job C
    //        ↘ Job B ↗
    const ydoc = createWorkflowYDoc({
      triggers: {
        'trigger-1': { id: 'trigger-1', type: 'webhook' },
      },
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common',
        },
        'job-c': {
          id: 'job-c',
          name: 'Job C',
          adaptor: '@openfn/language-common',
        },
      },
      edges: [
        { id: 'e1', source: 'trigger-1', target: 'job-a' },
        { id: 'e2', source: 'trigger-1', target: 'job-b' },
        { id: 'e3', source: 'job-a', target: 'job-c' },
        { id: 'e4', source: 'job-b', target: 'job-c' },
      ],
    });

    workflowStore = createConnectedWorkflowStore(ydoc);

    const { result } = renderHook(() => useJobDeleteValidation('job-c'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    expect(result.current.isFirstJob).toBe(false);
    expect(result.current.canDelete).toBe(true);
    expect(result.current.disableReason).toBe(null);
  });
});

describe('useJobDeleteValidation - Child Edge Validation', () => {
  let workflowStore: WorkflowStoreInstance;
  let sessionContextStore: SessionContextStoreInstance;
  let channelMock: any;

  beforeEach(() => {
    sessionContextStore = createSessionContextStore();
    channelMock = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(channelMock);
    sessionContextStore._connectChannel(mockProvider as any);
    setPermissions(channelMock, true);
  });

  test('blocks deletion of job with child edges (downstream dependencies)', () => {
    const ydoc = createWorkflowYDoc({
      triggers: {
        'trigger-1': { id: 'trigger-1', type: 'webhook' },
      },
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common',
        },
      },
      edges: [
        { id: 'e1', source: 'trigger-1', target: 'job-a' },
        { id: 'e2', source: 'job-a', target: 'job-b' },
      ],
    });

    workflowStore = createConnectedWorkflowStore(ydoc);

    const { result } = renderHook(() => useJobDeleteValidation('job-a'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    expect(result.current.hasChildEdges).toBe(true);
    expect(result.current.canDelete).toBe(false);
    expect(result.current.disableReason).toBe(
      'Cannot delete: other jobs depend on this step'
    );
  });

  test('allows deletion of job with no child edges (leaf node)', () => {
    const ydoc = createWorkflowYDoc({
      triggers: {
        'trigger-1': { id: 'trigger-1', type: 'webhook' },
      },
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common',
        },
      },
      edges: [
        { id: 'e1', source: 'trigger-1', target: 'job-a' },
        { id: 'e2', source: 'job-a', target: 'job-b' },
      ],
    });

    workflowStore = createConnectedWorkflowStore(ydoc);

    const { result } = renderHook(() => useJobDeleteValidation('job-b'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    expect(result.current.hasChildEdges).toBe(false);
    expect(result.current.canDelete).toBe(true);
    expect(result.current.disableReason).toBe(null);
  });

  test('blocks deletion of job with multiple child edges', () => {
    const ydoc = createWorkflowYDoc({
      triggers: {
        'trigger-1': { id: 'trigger-1', type: 'webhook' },
      },
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common',
        },
        'job-c': {
          id: 'job-c',
          name: 'Job C',
          adaptor: '@openfn/language-common',
        },
      },
      edges: [
        { id: 'e1', source: 'trigger-1', target: 'job-a' },
        { id: 'e2', source: 'job-a', target: 'job-b' },
        { id: 'e3', source: 'job-a', target: 'job-c' },
      ],
    });

    workflowStore = createConnectedWorkflowStore(ydoc);

    const { result } = renderHook(() => useJobDeleteValidation('job-a'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    expect(result.current.hasChildEdges).toBe(true);
    expect(result.current.canDelete).toBe(false);
    expect(result.current.disableReason).toBe(
      'Cannot delete: other jobs depend on this step'
    );
  });
});

describe('useJobDeleteValidation - Combined Validation Scenarios', () => {
  let workflowStore: WorkflowStoreInstance;
  let sessionContextStore: SessionContextStoreInstance;
  let channelMock: any;

  beforeEach(() => {
    sessionContextStore = createSessionContextStore();
    channelMock = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(channelMock);
    sessionContextStore._connectChannel(mockProvider as any);
  });

  test('shows highest priority message when multiple validations fail (permission > children > first)', () => {
    const ydoc = createWorkflowYDoc({
      triggers: {
        'trigger-1': { id: 'trigger-1', type: 'webhook' },
      },
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common',
        },
      },
      edges: [
        { id: 'e1', source: 'trigger-1', target: 'job-a' },
        { id: 'e2', source: 'job-a', target: 'job-b' },
      ],
    });

    workflowStore = createConnectedWorkflowStore(ydoc);
    setPermissions(channelMock, false);

    const { result } = renderHook(() => useJobDeleteValidation('job-a'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    // Should show permission message (highest priority)
    expect(result.current.canDelete).toBe(false);
    expect(result.current.disableReason).toBe(
      "You don't have permission to edit this workflow"
    );
    expect(result.current.isFirstJob).toBe(true);
    expect(result.current.hasChildEdges).toBe(true);
  });

  test('shows child edges message when permission passes but job has children', () => {
    const ydoc = createWorkflowYDoc({
      triggers: {
        'trigger-1': { id: 'trigger-1', type: 'webhook' },
      },
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common',
        },
      },
      edges: [
        { id: 'e1', source: 'trigger-1', target: 'job-a' },
        { id: 'e2', source: 'job-a', target: 'job-b' },
      ],
    });

    workflowStore = createConnectedWorkflowStore(ydoc);
    setPermissions(channelMock, true);

    const { result } = renderHook(() => useJobDeleteValidation('job-a'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    // Should show child edges message (second priority)
    expect(result.current.canDelete).toBe(false);
    expect(result.current.disableReason).toBe(
      'Cannot delete: other jobs depend on this step'
    );
  });

  test('returns all validation state when job passes all checks', () => {
    const ydoc = createWorkflowYDoc({
      triggers: {
        'trigger-1': { id: 'trigger-1', type: 'webhook' },
      },
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common',
        },
      },
      edges: [
        { id: 'e1', source: 'trigger-1', target: 'job-a' },
        { id: 'e2', source: 'job-a', target: 'job-b' },
      ],
    });

    workflowStore = createConnectedWorkflowStore(ydoc);
    setPermissions(channelMock, true);

    const { result } = renderHook(() => useJobDeleteValidation('job-b'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    // All checks pass
    expect(result.current).toEqual({
      canDelete: true,
      disableReason: null,
      hasChildEdges: false,
      isFirstJob: false,
    });
  });
});

describe('useJobDeleteValidation - Edge Case Scenarios', () => {
  let workflowStore: WorkflowStoreInstance;
  let sessionContextStore: SessionContextStoreInstance;
  let channelMock: any;

  beforeEach(() => {
    sessionContextStore = createSessionContextStore();
    channelMock = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(channelMock);
    sessionContextStore._connectChannel(mockProvider as any);
    setPermissions(channelMock, true);
  });

  test('handles non-existent job ID gracefully', () => {
    const ydoc = createWorkflowYDoc({
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
      },
      edges: [],
    });

    workflowStore = createConnectedWorkflowStore(ydoc);

    const { result } = renderHook(
      () => useJobDeleteValidation('non-existent-job'),
      {
        wrapper: createWrapper(workflowStore, sessionContextStore),
      }
    );

    // Non-existent job should be treated as having no edges or parents
    expect(result.current.canDelete).toBe(true);
    expect(result.current.disableReason).toBe(null);
    expect(result.current.hasChildEdges).toBe(false);
    expect(result.current.isFirstJob).toBe(false);
  });

  test('handles workflow with multiple triggers', () => {
    const ydoc = createWorkflowYDoc({
      triggers: {
        'trigger-1': { id: 'trigger-1', type: 'webhook' },
        'trigger-2': { id: 'trigger-2', type: 'cron' },
      },
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
      },
      edges: [
        { id: 'e1', source: 'trigger-1', target: 'job-a' },
        { id: 'e2', source: 'trigger-2', target: 'job-a' },
      ],
    });

    workflowStore = createConnectedWorkflowStore(ydoc);

    const { result } = renderHook(() => useJobDeleteValidation('job-a'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    // Job with only trigger parents is still a first job
    expect(result.current.isFirstJob).toBe(true);
    expect(result.current.canDelete).toBe(false);
    expect(result.current.disableReason).toBe(
      "You can't delete the first step in a workflow."
    );
  });

  test('handles empty workflow (no edges)', () => {
    const ydoc = createWorkflowYDoc({
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
      },
      edges: [],
    });

    workflowStore = createConnectedWorkflowStore(ydoc);

    const { result } = renderHook(() => useJobDeleteValidation('job-a'), {
      wrapper: createWrapper(workflowStore, sessionContextStore),
    });

    // Job with no edges can be deleted
    expect(result.current.canDelete).toBe(true);
    expect(result.current.disableReason).toBe(null);
    expect(result.current.hasChildEdges).toBe(false);
    expect(result.current.isFirstJob).toBe(false);
  });
});
