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
import { createEditorPreferencesStore } from '../../../../js/collaborative-editor/stores/createEditorPreferencesStore';
import type { EditorPreferencesStore } from '../../../../js/collaborative-editor/types/editorPreferences';

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
  historyStateOverride?: any
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
    } as any,
    uiStore: {} as any,
  };

  return ({ children }: { children: React.ReactNode }) => (
    <StoreContext.Provider value={mockStoreValue}>
      {children}
    </StoreContext.Provider>
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

      // Should start expanded - but since history is empty, it shows "No related history"
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

      // Use jsdom to set search params
      Object.defineProperty(window, 'location', {
        value: { search: '?run=test-run-id' },
        writable: true,
        configurable: true,
      });

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

      // Ensure URL has no run ID
      Object.defineProperty(window, 'location', {
        value: { search: '' },
        writable: true,
        configurable: true,
      });

      render(<CollaborativeWorkflowDiagram />, { wrapper });

      // Should respect stored expanded state - shows "No related history" when expanded with no data
      expect(screen.getByText(/No related history/i)).toBeInTheDocument();

      // Verify the store has the correct state
      expect(store.getSnapshot().historyPanelCollapsed).toBe(false);
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
      // Mock URL with run parameter
      const originalPushState = window.history.pushState;
      const pushStateMock = vi.fn();
      window.history.pushState = pushStateMock;

      // Set URL to have a run parameter (simulating user selected a run)
      const runId = '7d5e0711-e2fd-44a4-91cc-fa0c335f88e4';
      const mockUrl = new URL(`http://localhost/?run=${runId}`);
      Object.defineProperty(window, 'location', {
        value: {
          href: mockUrl.toString(),
          search: mockUrl.search,
          pathname: '/',
          origin: 'http://localhost',
        },
        writable: true,
        configurable: true,
      });

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

      // Run chip should be visible in collapsed state
      // Note: RunChip renders "Run {truncated-id}", look for this pattern
      expect(screen.getByText(/Run/i)).toBeInTheDocument();

      // Restore original pushState
      window.history.pushState = originalPushState;
    });

    test('run chip appears in collapsed state and can deselect run', async () => {
      // Mock URL with run parameter
      const originalPushState = window.history.pushState;
      const pushStateMock = vi.fn();
      window.history.pushState = pushStateMock;

      const runId = '7d5e0711-e2fd-44a4-91cc-fa0c335f88e4';
      const mockUrl = new URL(`http://localhost/?run=${runId}`);
      Object.defineProperty(window, 'location', {
        value: {
          href: mockUrl.toString(),
          search: mockUrl.search,
          pathname: '/',
          origin: 'http://localhost',
        },
        writable: true,
        configurable: true,
      });

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
      const closeButton = screen.getByLabelText(/Close run/i);
      fireEvent.click(closeButton);

      // Should clear URL parameter and hide chip
      await waitFor(() => {
        expect(pushStateMock).toHaveBeenCalled();
        const lastCall =
          pushStateMock.mock.calls[pushStateMock.mock.calls.length - 1];
        const urlArg = lastCall[2] as string;
        expect(urlArg).not.toContain('run=');
      });

      // Chip should be gone
      expect(screen.queryByText(/Run/i)).not.toBeInTheDocument();

      // Restore
      window.history.pushState = originalPushState;
    });
  });
});
