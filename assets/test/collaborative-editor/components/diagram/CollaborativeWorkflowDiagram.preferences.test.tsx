/**
 * CollaborativeWorkflowDiagram EditorPreferences Integration Tests
 *
 * Tests the integration of EditorPreferencesStore with
 * CollaborativeWorkflowDiagram for history panel collapsed state
 * persistence.
 */

import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import * as storage from 'lib0/storage';
import type React from 'react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { CollaborativeWorkflowDiagram } from '../../../../js/collaborative-editor/components/diagram/CollaborativeWorkflowDiagram';
import type { StoreContextValue } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { KeyboardProvider } from '../../../../js/collaborative-editor/keyboard';
import { createEditorPreferencesStore } from '../../../../js/collaborative-editor/stores/createEditorPreferencesStore';
import type { EditorPreferencesStore } from '../../../../js/collaborative-editor/types/editorPreferences';
import {
  createMockURLState,
  getURLStateMockValue,
} from '../../__helpers__/urlStateMocks';

// Helper to create a withSelector mock that implements proper caching
// Must be defined before mocks to avoid JSX parsing issues
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

function createWrapper(
  editorPreferencesStore: EditorPreferencesStore,
  historyStateOverride?: any,
  historyStoreOverride?: Record<string, any>,
  sessionStateOverride?: Record<string, any>
): React.ComponentType<{ children: React.ReactNode }> {
  // Create mock stores with proper getSnapshot functions
  const workflowState = {
    workflow: { jobs: [], triggers: [], edges: [] },
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
    ...sessionStateOverride,
  };
  const historyState = historyStateOverride || {
    history: [],
    loading: false,
    error: null,
    channelConnected: false,
    runStepsCache: {},
    runStepsSubscribers: {},
    runStepsLoading: new Set(),
  };

  const workflowGetSnapshot = () => workflowState;
  const sessionGetSnapshot = () => sessionState;
  const historyGetSnapshot = () => historyState;

  const mockStoreValue: StoreContextValue = {
    editorPreferencesStore,
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
      requestVersions: vi.fn(),
    } as any,
    historyStore: {
      getSnapshot: historyGetSnapshot,
      subscribe: () => () => {},
      withSelector: createWithSelectorMock(historyGetSnapshot),
      requestHistory: vi.fn(),
      clearError: vi.fn(),
      getRunSteps: vi.fn(() => null),
      requestRunSteps: vi.fn(() => Promise.resolve(null)),
      subscribeToRunSteps: vi.fn(),
      unsubscribeFromRunSteps: vi.fn(),
      _viewRun: vi.fn(),
      _closeRunViewer: vi.fn(),
      ...historyStoreOverride,
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

describe('CollaborativeWorkflowDiagram - EditorPreferences Integration', () => {
  let store: EditorPreferencesStore;
  let wrapper: React.ComponentType<{ children: React.ReactNode }>;

  beforeEach(() => {
    // Clear storage
    storage.varStorage.clear?.() ||
      Object.keys(storage.varStorage).forEach(key =>
        storage.varStorage.removeItem(key)
      );

    // Reset URL mock
    urlState.reset();

    // Create fresh store and wrapper for each test
    store = createEditorPreferencesStore();
    wrapper = createWrapper(store);
  });

  afterEach(() => {
    storage.varStorage.clear?.() ||
      Object.keys(storage.varStorage).forEach(key =>
        storage.varStorage.removeItem(key)
      );
  });

  // ========================================================================
  // STORAGE PERSISTENCE
  // ========================================================================

  describe('storage persistence', () => {
    test('history panel uses default collapsed state on first render', () => {
      render(<CollaborativeWorkflowDiagram />, { wrapper });

      // MiniHistory should start collapsed (default)
      const historyPanel = screen.getByText(/View History/i);
      expect(historyPanel).toBeInTheDocument();
    });

    test('history panel loads saved collapsed state from storage', () => {
      // Pre-populate storage with expanded state
      storage.varStorage.setItem(
        'lightning.editor.historyPanelCollapsed',
        'false'
      );

      // Recreate store after setting storage
      store = createEditorPreferencesStore();
      wrapper = createWrapper(store);

      render(<CollaborativeWorkflowDiagram />, { wrapper });

      // Should start expanded - but since history is empty, it shows the
      // empty state.
      const noHistoryText = screen.queryByText(/No related history/i);
      expect(noHistoryText).toBeInTheDocument();

      // Verify storage was read
      expect(store.getSnapshot().historyPanelCollapsed).toBe(false);
    });

    test('toggling history panel saves state to storage', async () => {
      render(<CollaborativeWorkflowDiagram />, { wrapper });

      // Find and click toggle button
      const toggleButton = screen.getByText(/View History/i).closest('div');
      fireEvent.click(toggleButton!);

      // Wait for state update
      await waitFor(() => {
        const stored = storage.varStorage.getItem(
          'lightning.editor.historyPanelCollapsed'
        );
        expect(stored).toBe('false');
      });
    });

    test('collapsed state persists across re-renders', async () => {
      const { rerender } = render(<CollaborativeWorkflowDiagram />, {
        wrapper,
      });

      // Toggle to expanded
      const toggleButton = screen.getByText(/View History/i).closest('div');
      fireEvent.click(toggleButton!);

      await waitFor(() => {
        expect(screen.getByText(/Recent History/i)).toBeInTheDocument();
      });

      // Rerender component
      rerender(<CollaborativeWorkflowDiagram />);

      // Should still be expanded
      expect(screen.getByText(/Recent History/i)).toBeInTheDocument();
    });
  });

  // ========================================================================
  // URL OVERRIDE BEHAVIOR
  // ========================================================================

  describe('URL override behavior', () => {
    test('respects stored collapsed state even with run ID in URL', async () => {
      // Set collapsed state in storage
      storage.varStorage.setItem(
        'lightning.editor.historyPanelCollapsed',
        'true'
      );

      // Set URL with run parameter
      urlState.setParams({ run: 'test-run-id' });

      render(<CollaborativeWorkflowDiagram />, { wrapper });

      // Panel should stay collapsed (no auto-expand)
      await waitFor(() => {
        expect(screen.queryByText(/Recent History/i)).not.toBeInTheDocument();
        expect(screen.getByText(/View History/i)).toBeInTheDocument();
      });

      // Storage should remain unchanged
      const stored = storage.varStorage.getItem(
        'lightning.editor.historyPanelCollapsed'
      );
      expect(stored).toBe('true');
    });

    test('respects stored state when no run ID in URL', () => {
      // Set expanded state in storage
      storage.varStorage.setItem(
        'lightning.editor.historyPanelCollapsed',
        'false'
      );

      // Recreate store after setting storage
      store = createEditorPreferencesStore();
      wrapper = createWrapper(store);

      // Ensure URL has no run ID (reset clears all params)
      urlState.clearParams();

      render(<CollaborativeWorkflowDiagram />, { wrapper });

      // Empty state when expanded with no runs
      expect(screen.getByText(/No related history/i)).toBeInTheDocument();

      // Verify the store has the correct state
      expect(store.getSnapshot().historyPanelCollapsed).toBe(false);
    });
  });

  // ========================================================================
  // RUN-SELECT vs DROPDOWN VERSION SWITCH (distinct clear behavior)
  // ========================================================================

  describe('run-select vs version switch', () => {
    test('a dropdown version switch clears the run (URL + run viewer/overlay)', async () => {
      storage.varStorage.setItem(
        'lightning.editor.historyPanelCollapsed',
        'false'
      );
      store = createEditorPreferencesStore();

      // A run is selected: present in the URL AND held by the history store as
      // the active run (which drives the canvas step overlay).
      const closeRunViewer = vi.fn();
      wrapper = createWrapper(
        store,
        {
          history: [],
          isLoading: false,
          error: null,
          isChannelConnected: true,
          activeRun: { id: 'stale-run' },
          runStepsCache: {},
          runStepsSubscribers: {},
          runStepsLoading: new Set(),
        },
        { _closeRunViewer: closeRunViewer }
      );

      // Start on latest with the run selected.
      urlState.setParams({ run: 'stale-run' });

      const { rerender } = render(<CollaborativeWorkflowDiagram />, { wrapper });

      // Dropdown switch to version 2: the ?v param changes with NO run-select in
      // progress. Even if ?run lingers, the diagram must drop it and close the
      // store's active run so the stale run does not persist on the new version.
      urlState.setParams({ v: '2' });
      rerender(<CollaborativeWorkflowDiagram />);

      await waitFor(() => {
        // Overlay source cleared (history store active run closed).
        expect(closeRunViewer).toHaveBeenCalled();
        // Residual run param dropped from the URL.
        expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
          run: null,
        });
      });
    });

    test('clicking a run of a different version loads it as-executed WITHOUT clearing it', async () => {
      storage.varStorage.setItem(
        'lightning.editor.historyPanelCollapsed',
        'false'
      );
      store = createEditorPreferencesStore();

      // Make the URL mock actually apply updates so the reconcile effect sees
      // the ?v change that selecting a different-version run produces.
      urlState.mockFns.updateSearchParams.mockImplementation(
        (updates: Record<string, string | number | boolean | null>) => {
          for (const [key, value] of Object.entries(updates)) {
            if (value === null) delete urlState.mockParams[key];
            else urlState.mockParams[key] = String(value);
          }
        }
      );

      const closeRunViewer = vi.fn();
      wrapper = createWrapper(
        store,
        {
          history: [
            {
              id: 'wo-1',
              version: 5,
              state: 'success',
              last_activity: '2025-10-23T21:00:02.293382Z',
              runs: [
                {
                  id: 'run-old',
                  state: 'success',
                  error_type: null,
                  started_at: '2025-10-23T20:59:58Z',
                  finished_at: '2025-10-23T21:00:02Z',
                  version: 5,
                },
              ],
            },
          ],
          isLoading: false,
          error: null,
          isChannelConnected: true,
          runStepsCache: {},
          runStepsSubscribers: {},
          runStepsLoading: new Set(),
        },
        { _closeRunViewer: closeRunViewer },
        // Current version is 9; the run above is v5 → different → as-executed.
        { latestSnapshotLockVersion: 9 }
      );

      // Start pinned to v2, so selecting the run (which clears ?v) is a genuine
      // ?v change — the exact case that must NOT be treated as a version switch.
      urlState.setParams({ v: '2' });

      const { rerender } = render(<CollaborativeWorkflowDiagram />, { wrapper });

      // Expand the single-run work order → auto-selects the run.
      fireEvent.click(
        screen.getByRole('button', { name: /Expand work order details/i })
      );
      rerender(<CollaborativeWorkflowDiagram />);

      await waitFor(() => {
        // Loaded as-executed: ?as_run set to the run, ?v cleared.
        expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
          v: null,
          as_run: 'run-old',
          run: 'run-old',
        });
      });

      // Crucially, the run it just selected was NOT cleared.
      expect(closeRunViewer).not.toHaveBeenCalled();
      expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalledWith({
        run: null,
      });
    });
  });

  // ========================================================================
  // STORAGE KEY MIGRATION
  // ========================================================================

  describe('storage key migration', () => {
    test("does NOT migrate old 'history-panel-collapsed' key", () => {
      // Old key exists
      storage.varStorage.setItem('history-panel-collapsed', 'false');

      render(<CollaborativeWorkflowDiagram />, { wrapper });

      // Should use default, NOT migrate old key
      expect(screen.getByText(/View History/i)).toBeInTheDocument();

      // New key should not be set (until user toggles)
      const newKey = storage.varStorage.getItem(
        'lightning.editor.historyPanelCollapsed'
      );
      expect(newKey).toBeNull();
    });
  });

  // ========================================================================
  // RUN SELECTION AND PANEL COLLAPSE
  // ========================================================================

  describe('run selection and panel collapse', () => {
    test('collapsing panel keeps run selected', async () => {
      // Set URL to have a run parameter (simulating user selected a run)
      const runId = '7d5e0711-e2fd-44a4-91cc-fa0c335f88e4';
      urlState.setParams({ run: runId });

      // Pre-expand the history panel (simulating auto-expand when run selected)
      storage.varStorage.setItem(
        'lightning.editor.historyPanelCollapsed',
        'false'
      );
      store = createEditorPreferencesStore();

      // Create a wrapper with mock history data
      const mockHistoryState = {
        history: [
          {
            id: 'e2107d46-cf29-4930-b11b-cbcfcf83549d',
            version: 29,
            state: 'success' as const,
            runs: [
              {
                id: runId,
                state: 'success' as const,
                started_at: '2025-10-23T21:00:01.106711Z',
                finished_at: '2025-10-23T21:00:02.098356Z',
                error_type: null,
              },
            ],
            last_activity: '2025-10-23T21:00:02.293382Z',
          },
        ],
        loading: false,
        error: null,
        channelConnected: false,
        runStepsCache: {},
        runStepsSubscribers: {},
        runStepsLoading: new Set(),
      };

      // Create wrapper with mock history
      wrapper = createWrapper(store, mockHistoryState);

      render(<CollaborativeWorkflowDiagram />, { wrapper });

      // Panel should be expanded
      await waitFor(() => {
        expect(screen.getByText(/Recent History/i)).toBeInTheDocument();
      });

      // Click to collapse the panel
      const collapseButton = screen.getByText(/Recent History/i).closest('div');
      fireEvent.click(collapseButton!);

      // Panel should collapse but run should stay selected (no pushState to clear URL)
      await waitFor(() => {
        expect(screen.getByText(/View History/i)).toBeInTheDocument();
      });

      // Run badge should be visible in collapsed state
      // Note: RunBadge renders "Run {truncated-id}", look for this pattern
      expect(screen.getByText(/Run/i)).toBeInTheDocument();
    });

    test('run chip appears in collapsed state and can deselect run', async () => {
      const runId = '7d5e0711-e2fd-44a4-91cc-fa0c335f88e4';
      urlState.setParams({ run: runId });

      // Start with panel expanded and run selected
      storage.varStorage.setItem(
        'lightning.editor.historyPanelCollapsed',
        'false'
      );
      store = createEditorPreferencesStore();

      // Create a wrapper with mock history data
      const mockHistoryState = {
        history: [
          {
            id: 'e2107d46-cf29-4930-b11b-cbcfcf83549d',
            version: 29,
            state: 'success' as const,
            runs: [
              {
                id: runId,
                state: 'success' as const,
                started_at: '2025-10-23T21:00:01.106711Z',
                finished_at: '2025-10-23T21:00:02.098356Z',
                error_type: null,
              },
            ],
            last_activity: '2025-10-23T21:00:02.293382Z',
          },
        ],
        loading: false,
        error: null,
        channelConnected: false,
        runStepsCache: {},
        runStepsSubscribers: {},
        runStepsLoading: new Set(),
      };

      // Create wrapper with mock history
      wrapper = createWrapper(store, mockHistoryState);

      render(<CollaborativeWorkflowDiagram />, { wrapper });

      // Collapse the panel
      const collapseButton = screen.getByText(/Recent History/i).closest('div');
      fireEvent.click(collapseButton!);

      // Run chip should appear in collapsed state
      await waitFor(() => {
        expect(screen.getByText(/View History/i)).toBeInTheDocument();
        expect(screen.getByText(/Run/i)).toBeInTheDocument();
      });

      // Click the X button on the chip to deselect
      const closeButton = screen.getByLabelText(/Remove/i);
      fireEvent.click(closeButton);

      // Should call updateSearchParams to clear the run selection and any
      // as-executed view, returning to the current editable canvas.
      await waitFor(() => {
        expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
          run: null,
          as_run: null,
        });
      });

      // Note: Testing that the chip disappears after URL change requires
      // reactive URL state behavior that the centralized mock doesn't provide.
      // The important behavior (calling updateSearchParams) is already verified above.
    });
  });
});
