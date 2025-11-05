/**
 * CollaborativeWorkflowDiagram Real-time Run Updates Tests
 *
 * Tests that run visualization updates in real-time as runs progress
 * when history_updated messages are received from the channel.
 */

import { render, waitFor } from '@testing-library/react';
import type React from 'react';
import { describe, expect, test, beforeEach, vi } from 'vitest';
import { CollaborativeWorkflowDiagram } from '../../../../js/collaborative-editor/components/diagram/CollaborativeWorkflowDiagram';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import type { StoreContextValue } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import type {
  WorkOrder,
  Run,
  RunStepsData,
} from '../../../../js/collaborative-editor/types/history';

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
    channelConnected: boolean;
    runStepsCache: Record<string, RunStepsData>;
    runStepsSubscribers: Record<string, Set<string>>;
    runStepsLoading: Set<string>;
  };
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
          historySubscribers.add(callback);
          return () => historySubscribers.delete(callback);
        },
        withSelector: createWithSelectorMock(historyGetSnapshot),
        requestHistory: vi.fn(),
        clearError: vi.fn(),
        getRunSteps: getRunStepsMock,
        requestRunSteps: requestRunStepsMock,
        subscribeToRunSteps: vi.fn(),
        unsubscribeFromRunSteps: vi.fn(),
      } as any,
      uiStore: {} as any,
      runStore: {} as any,
    };

    return ({ children }: { children: React.ReactNode }) => (
      <StoreContext.Provider value={mockStoreValue}>
        {children}
      </StoreContext.Provider>
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
      channelConnected: true,
      runStepsCache: {},
      runStepsSubscribers: {},
      runStepsLoading: new Set(),
    };

    // Mock URL with run ID
    Object.defineProperty(window, 'location', {
      value: {
        search: '?run=run-1',
        href: 'http://localhost?run=run-1',
      },
      writable: true,
      configurable: true,
    });
    window.history.pushState = vi.fn();
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

    // Simulate first update: "started" -> "running"
    historyState = {
      ...historyState,
      history: [
        {
          ...historyState.history[0],
          runs: [
            {
              ...historyState.history[0].runs[0],
              state: 'started',
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
    Object.defineProperty(window, 'location', {
      value: {
        search: '',
        href: 'http://localhost',
      },
      writable: true,
      configurable: true,
    });

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

    // Should re-fetch for run-1 (selected) even though run-2 changed
    // This is expected behavior - we re-fetch whenever history updates
    // and a run is selected (could be optimized in future to only
    // re-fetch if the selected run itself changed)
    await waitFor(() => {
      expect(requestRunStepsMock).toHaveBeenCalledTimes(2);
      expect(requestRunStepsMock).toHaveBeenCalledWith('run-1');
    });
  });
});
