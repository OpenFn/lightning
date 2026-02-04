/**
 * CollaborativeWorkflowDiagram Real-time Run Updates Tests
 *
 * Tests that run visualization updates in real-time as runs progress
 * when history_updated messages are received from the channel.
 */

import { render, waitFor } from '@testing-library/react';
import type React from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import { CollaborativeWorkflowDiagram } from '../../../../js/collaborative-editor/components/diagram/CollaborativeWorkflowDiagram';
import type { StoreContextValue } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { KeyboardProvider } from '../../../../js/collaborative-editor/keyboard';
import type {
  Run,
  RunStepsData,
  WorkOrder,
} from '../../../../js/collaborative-editor/types/history';
import {
  createMockURLState,
  getURLStateMockValue,
} from '../../__helpers__/urlStateMocks';

// Helper to create a withSelector mock that implements proper caching
function createWithSelectorMock(getSnapshot: () => any) {
  return function (selector: (state: any) => any) {
    let lastResult: any;
    let lastState: any;

    return function (): any {
      const currentState = getSnapshot();

      // Only recompute if state reference actually changed
      if (currentState !== lastState) {
        lastResult = selector(currentState);
        lastState = currentState;
      }

      return lastResult;
    };
  };
}

// Mock useURLState using centralized helper
const urlState = createMockURLState();

vi.mock('../../../../js/react/lib/use-url-state', () => ({
  useURLState: () => getURLStateMockValue(urlState),
}));

// Mock dependencies
vi.mock('@xyflow/react', () => ({
  ReactFlow: () => <div data-testid="react-flow">Workflow Diagram</div>,
  ReactFlowProvider: ({ children }: { children: React.ReactNode }) => (
    <div>{children}</div>
  ),
  Background: () => null,
  Controls: () => null,
  MiniMap: () => null,
  useReactFlow: () => ({
    fitView: vi.fn(),
  }),
}));

// Mock WorkflowDiagram implementation
vi.mock(
  '../../../../js/collaborative-editor/components/diagram/WorkflowDiagram',
  () => ({
    default: () => <div data-testid="workflow-diagram-impl" />,
  })
);

// Mock hooks module to avoid Phoenix LiveView dependencies
vi.mock('../../../../js/hooks', () => ({
  relativeLocale: {},
}));

// Mock date-fns formatRelative to avoid locale issues in tests
vi.mock('date-fns', async () => {
  const actual = await vi.importActual('date-fns');
  return {
    ...actual,
    formatRelative: vi.fn(() => '2 hours ago'),
  };
});

describe('CollaborativeWorkflowDiagram - Real-time Run Updates', () => {
  let historyState: {
    history: WorkOrder[];
    loading: boolean;
    error: null;
    isChannelConnected: boolean;
    runStepsCache: Record<string, RunStepsData>;
    runStepsSubscribers: Record<string, Set<string>>;
    runStepsLoading: Set<string>;
  };
  let previousHistoryState: typeof historyState;
  let historySubscribers: Set<() => void>;
  let requestRunStepsMock: ReturnType<typeof vi.fn>;
  let getRunStepsMock: ReturnType<typeof vi.fn>;

  function createWrapper(): React.ComponentType<{
    children: React.ReactNode;
  }> {
    const workflowState = {
      workflow: { id: 'workflow-1', jobs: [], triggers: [], edges: [] },
      selectedNode: { type: 'job' as const, id: null },
    };
    const sessionState = {
      isNewWorkflow: false,
      project: {},
      user: {},
      loading: false,
      error: null,
      config: {},
      permissions: {},
    };

    const workflowGetSnapshot = () => workflowState;
    const sessionGetSnapshot = () => sessionState;
    const historyGetSnapshot = () => historyState;

    const mockStoreValue: StoreContextValue = {
      editorPreferencesStore: {
        getSnapshot: () => ({ historyPanelCollapsed: false }),
        subscribe: () => () => {},
        withSelector: (selector: any) => () =>
          selector({ historyPanelCollapsed: false }),
      } as any,
      adaptorStore: {} as any,
      credentialStore: {} as any,
      awarenessStore: {} as any,
      workflowStore: {
        getSnapshot: workflowGetSnapshot,
        subscribe: () => () => {},
        withSelector: createWithSelectorMock(workflowGetSnapshot),
        selectNode: () => {},
      } as any,
      sessionContextStore: {
        getSnapshot: sessionGetSnapshot,
        subscribe: () => () => {},
        withSelector: createWithSelectorMock(sessionGetSnapshot),
      } as any,
      historyStore: {
        getSnapshot: historyGetSnapshot,
        subscribe: (callback: () => void) => {
          const enhancedCallback = () => {
            // Simulate cache invalidation on history update
            // Detect which runs changed by comparing states
            const currentState = historyGetSnapshot();
            const changedRunIds = new Set<string>();

            // Check which runs have changed state
            currentState.history.forEach(wo => {
              wo.runs.forEach(run => {
                const prevWo = previousHistoryState?.history.find(
                  w => w.id === wo.id
                );
                const prevRun = prevWo?.runs.find(r => r.id === run.id);

                if (
                  !prevRun ||
                  prevRun.state !== run.state ||
                  prevRun.finished_at !== run.finished_at ||
                  prevRun.started_at !== run.started_at
                ) {
                  changedRunIds.add(run.id);
                }
              });
            });

            // For each changed run that has subscribers, invalidate cache and refetch
            changedRunIds.forEach(runId => {
              if (currentState.runStepsSubscribers[runId]?.size > 0) {
                // Invalidate cache
                delete currentState.runStepsCache[runId];
                // Trigger refetch
                void requestRunStepsMock(runId);
              }
            });

            // Update previous state for next comparison (deep clone)
            previousHistoryState = {
              ...currentState,
              history: currentState.history.map(wo => ({
                ...wo,
                runs: [...wo.runs],
              })),
              runStepsCache: { ...currentState.runStepsCache },
              runStepsSubscribers: { ...currentState.runStepsSubscribers },
              runStepsLoading: new Set(currentState.runStepsLoading),
            };

            // Call original callback
            callback();
          };
          historySubscribers.add(enhancedCallback);
          return () => historySubscribers.delete(enhancedCallback);
        },
        withSelector: createWithSelectorMock(historyGetSnapshot),
        requestHistory: vi.fn(),
        clearError: vi.fn(),
        getRunSteps: getRunStepsMock,
        requestRunSteps: requestRunStepsMock,
        subscribeToRunSteps: vi.fn((runId: string, subscriberId: string) => {
          // Add to subscribers
          const state = historyGetSnapshot();
          if (!state.runStepsSubscribers[runId]) {
            state.runStepsSubscribers[runId] = new Set();
          }
          state.runStepsSubscribers[runId].add(subscriberId);

          // Fetch if not cached
          if (
            !state.runStepsCache[runId] &&
            !state.runStepsLoading.has(runId)
          ) {
            void requestRunStepsMock(runId);
          }
        }),
        unsubscribeFromRunSteps: vi.fn(
          (runId: string, subscriberId: string) => {
            const state = historyGetSnapshot();
            if (state.runStepsSubscribers[runId]) {
              state.runStepsSubscribers[runId].delete(subscriberId);
            }
          }
        ),
        _viewRun: vi.fn(),
      } as any,
      uiStore: {} as any,
    };

    return ({ children }: { children: React.ReactNode }) => (
      <KeyboardProvider>
        <StoreContext.Provider value={mockStoreValue}>
          {children}
        </StoreContext.Provider>
      </KeyboardProvider>
    );
  }

  beforeEach(() => {
    historySubscribers = new Set();

    // Mock run steps data
    const mockRunStepsData: RunStepsData = {
      run_id: 'run-1',
      steps: [
        {
          id: 'step-1',
          job_id: 'job-1',
          exit_reason: 'success',
          error_type: null,
          started_at: '2024-01-01T10:00:00Z',
          finished_at: '2024-01-01T10:01:00Z',
          input_dataclip_id: 'dataclip-1',
        },
      ],
      metadata: {
        starting_job_id: 'job-1',
        starting_trigger_id: null,
        inserted_at: '2024-01-01T10:00:00Z',
        created_by_id: 'user-1',
        created_by_email: 'demo@openfn.org',
      },
    };

    requestRunStepsMock = vi.fn(() => Promise.resolve(mockRunStepsData));
    getRunStepsMock = vi.fn(() => null);

    // Initial history state with a run in "started" state
    historyState = {
      history: [
        {
          id: 'wo-1',
          state: 'running',
          last_activity: '2024-01-01T10:00:00Z',
          version: 1,
          runs: [
            {
              id: 'run-1',
              state: 'started',
              error_type: null,
              started_at: '2024-01-01T10:00:00Z',
              finished_at: null,
            } as Run,
          ],
        } as WorkOrder,
      ],
      loading: false,
      error: null,
      isChannelConnected: true,
      runStepsCache: {},
      runStepsSubscribers: {},
      runStepsLoading: new Set(),
    };

    // Initialize previous state for comparison (deep clone)
    previousHistoryState = {
      ...historyState,
      history: historyState.history.map(wo => ({ ...wo, runs: [...wo.runs] })),
      runStepsCache: { ...historyState.runStepsCache },
      runStepsSubscribers: { ...historyState.runStepsSubscribers },
      runStepsLoading: new Set(historyState.runStepsLoading),
    };

    // Reset URL mock to have run-1 selected (default for most tests)
    urlState.reset();
    urlState.setParams({ run: 'run-1' });
  });

  test('re-fetches run steps when history updates for selected run', async () => {
    const wrapper = createWrapper();
    render(<CollaborativeWorkflowDiagram />, { wrapper });

    // Wait for initial fetch
    await waitFor(() => {
      expect(requestRunStepsMock).toHaveBeenCalledTimes(1);
      expect(requestRunStepsMock).toHaveBeenCalledWith('run-1');
    });

    // Simulate history update: run transitions from "started" to "success"
    historyState = {
      ...historyState,
      history: [
        {
          ...historyState.history[0],
          state: 'success',
          runs: [
            {
              id: 'run-1',
              state: 'success',
              error_type: null,
              started_at: '2024-01-01T10:00:00Z',
              finished_at: '2024-01-01T10:01:00Z',
            } as Run,
          ],
        } as WorkOrder,
      ],
    };

    // Notify subscribers of history update
    historySubscribers.forEach(callback => callback());

    // Wait for re-fetch
    await waitFor(() => {
      // Should have been called twice: initial + after history update
      expect(requestRunStepsMock).toHaveBeenCalledTimes(2);
    });
  });

  test('re-fetches run steps multiple times as run progresses', async () => {
    const wrapper = createWrapper();
    render(<CollaborativeWorkflowDiagram />, { wrapper });

    // Wait for initial fetch
    await waitFor(() => {
      expect(requestRunStepsMock).toHaveBeenCalledTimes(1);
    });

    // Simulate first update: run still executing (started_at gets updated or steps change)
    // We update the started_at timestamp to simulate progress
    historyState = {
      ...historyState,
      history: [
        {
          ...historyState.history[0],
          runs: [
            {
              ...historyState.history[0].runs[0],
              state: 'started',
              started_at: '2024-01-01T10:00:30Z', // 30 seconds later
            } as Run,
          ],
        } as WorkOrder,
      ],
    };
    historySubscribers.forEach(callback => callback());

    await waitFor(() => {
      expect(requestRunStepsMock).toHaveBeenCalledTimes(2);
    });

    // Simulate second update: "started" -> "success"
    historyState = {
      ...historyState,
      history: [
        {
          ...historyState.history[0],
          state: 'success',
          runs: [
            {
              ...historyState.history[0].runs[0],
              state: 'success',
              finished_at: '2024-01-01T10:01:00Z',
            } as Run,
          ],
        } as WorkOrder,
      ],
    };
    historySubscribers.forEach(callback => callback());

    await waitFor(() => {
      expect(requestRunStepsMock).toHaveBeenCalledTimes(3);
    });
  });

  test('does not re-fetch when no run is selected', async () => {
    // Remove run ID from URL
    urlState.clearParams();

    const wrapper = createWrapper();
    render(<CollaborativeWorkflowDiagram />, { wrapper });

    // Should not fetch initially (no selected run)
    await new Promise(resolve => setTimeout(resolve, 100));
    expect(requestRunStepsMock).not.toHaveBeenCalled();

    // Simulate history update
    historyState = {
      ...historyState,
      history: [
        {
          ...historyState.history[0],
          state: 'success',
        } as WorkOrder,
      ],
    };
    historySubscribers.forEach(callback => callback());

    // Should still not fetch (no selected run)
    await new Promise(resolve => setTimeout(resolve, 100));
    expect(requestRunStepsMock).not.toHaveBeenCalled();
  });

  test('only re-fetches for the currently selected run', async () => {
    // Add a second run to history
    historyState = {
      ...historyState,
      history: [
        {
          ...historyState.history[0],
          runs: [
            ...historyState.history[0].runs,
            {
              id: 'run-2',
              state: 'started',
              error_type: null,
              started_at: '2024-01-01T10:05:00Z',
              finished_at: null,
            } as Run,
          ],
        } as WorkOrder,
      ],
    };

    const wrapper = createWrapper();
    render(<CollaborativeWorkflowDiagram />, { wrapper });

    // Wait for initial fetch of run-1 (from URL)
    await waitFor(() => {
      expect(requestRunStepsMock).toHaveBeenCalledTimes(1);
      expect(requestRunStepsMock).toHaveBeenCalledWith('run-1');
    });

    // Simulate update to run-2 (not selected)
    historyState = {
      ...historyState,
      history: [
        {
          ...historyState.history[0],
          runs: [
            historyState.history[0].runs[0],
            {
              ...historyState.history[0].runs[1],
              state: 'success',
              finished_at: '2024-01-01T10:06:00Z',
            } as Run,
          ],
        } as WorkOrder,
      ],
    };
    historySubscribers.forEach(callback => callback());

    // Should NOT re-fetch for run-1 since only run-2 changed
    // The new implementation only refetches when the selected run itself changes
    // This is more efficient than refetching on every history update
    await new Promise(resolve => setTimeout(resolve, 100));
    expect(requestRunStepsMock).toHaveBeenCalledTimes(1); // Still just the initial fetch
    expect(requestRunStepsMock).toHaveBeenCalledWith('run-1');
  });
});
