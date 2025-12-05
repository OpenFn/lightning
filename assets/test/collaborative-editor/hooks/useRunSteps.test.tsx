/**
 * useRunSteps Hook Tests
 *
 * Tests for the useRunSteps hook that provides automatic subscription
 * management for run steps data.
 */

import { renderHook, waitFor } from '@testing-library/react';
import type React from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import * as Y from 'yjs';

import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { useRunSteps } from '../../../js/collaborative-editor/hooks/useHistory';
import type { HistoryStoreInstance } from '../../../js/collaborative-editor/stores/createHistoryStore';
import { createHistoryStore } from '../../../js/collaborative-editor/stores/createHistoryStore';
import { createWorkflowStore } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import type { RunStepsData } from '../../../js/collaborative-editor/types/history';
import type { Session } from '../../../js/collaborative-editor/types/session';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../mocks/phoenixChannel';

// Mock useId to return stable test ID
vi.mock('react', async () => {
  const actual = await vi.importActual('react');
  return {
    ...actual,
    useId: () => ':test-id:',
  };
});

function createWrapper(
  historyStore: HistoryStoreInstance
): React.ComponentType<{ children: React.ReactNode }> {
  const workflowStore = createWorkflowStore();

  // Create Y.Doc and set up workflow data
  const ydoc = new Y.Doc() as Session.WorkflowDoc;
  const workflowMap = ydoc.getMap('workflow');
  workflowMap.set('id', 'workflow-test-id');
  workflowMap.set('name', 'Test Workflow');

  // Initialize empty arrays for jobs, triggers, edges
  ydoc.getArray('jobs');
  ydoc.getArray('triggers');
  ydoc.getArray('edges');
  ydoc.getMap('positions');

  // Connect workflow store to Y.Doc
  const mockChannel = createMockPhoenixChannel('test:room');
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);
  (mockProvider as any).doc = ydoc;
  workflowStore.connect(ydoc, mockProvider as any);

  const mockStoreValue: StoreContextValue = {
    historyStore,
    workflowStore,
    sessionContextStore: {} as any,
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

describe('useRunSteps', () => {
  let historyStore: HistoryStoreInstance;

  beforeEach(() => {
    historyStore = createHistoryStore();
  });

  test('returns null when runId is null', () => {
    const mockChannel = createMockPhoenixChannel('workflow:test');
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);

    historyStore._connectChannel(mockProvider as any);

    const wrapper = createWrapper(historyStore);

    const { result } = renderHook(() => useRunSteps(null), { wrapper });

    expect(result.current).toBeNull();
  });

  test('subscribes on mount and unsubscribes on unmount', () => {
    const subscribeSpy = vi.spyOn(historyStore, 'subscribeToRunSteps');
    const unsubscribeSpy = vi.spyOn(historyStore, 'unsubscribeFromRunSteps');

    // Connect history channel so isHistoryChannelConnected returns true
    const mockChannel = createMockPhoenixChannel('workflow:test');
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    historyStore._connectChannel(mockProvider as any);

    const wrapper = createWrapper(historyStore);

    const { unmount } = renderHook(() => useRunSteps('run-test'), { wrapper });

    expect(subscribeSpy).toHaveBeenCalledWith('run-test', ':test-id:');

    unmount();

    expect(unsubscribeSpy).toHaveBeenCalledWith('run-test', ':test-id:');
  });

  test('transforms RunStepsData to RunInfo', async () => {
    const mockChannel = createMockPhoenixChannel('workflow:test');
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);

    historyStore._connectChannel(mockProvider as any);

    const mockRunSteps: RunStepsData = {
      run_id: 'run-transform',
      steps: [
        {
          id: 'step-1',
          job_id: 'job-1',
          exit_reason: 'success',
          error_type: null,
          started_at: '2025-01-08T10:00:00Z',
          finished_at: '2025-01-08T10:01:00Z',
          input_dataclip_id: 'clip-1',
        },
      ],
      metadata: {
        starting_job_id: 'job-1',
        starting_trigger_id: null,
        inserted_at: '2025-01-08T09:59:00Z',
        created_by_id: 'user-1',
        created_by_email: 'test@example.com',
      },
    };

    mockChannel.push = () =>
      ({
        receive: (status: string, callback: (response?: unknown) => void) => {
          if (status === 'ok') {
            setTimeout(() => callback(mockRunSteps), 0);
          }
          return { receive: () => ({ receive: () => ({}) }) };
        },
      }) as any;

    const wrapper = createWrapper(historyStore);

    const { result } = renderHook(() => useRunSteps('run-transform'), {
      wrapper,
    });

    await waitFor(() => {
      expect(result.current).not.toBeNull();
    });

    // Verify transformation
    expect(result.current).toMatchObject({
      start_from: 'job-1',
      inserted_at: '2025-01-08T09:59:00Z',
      isTrigger: false,
      run_by: 'test@example.com',
      steps: expect.arrayContaining([
        expect.objectContaining({
          id: 'step-1',
          job_id: 'job-1',
          exit_reason: 'success',
          startNode: true,
          startBy: 'test@example.com',
        }),
      ]),
    });
  });
});
