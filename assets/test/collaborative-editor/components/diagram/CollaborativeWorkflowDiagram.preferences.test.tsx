/**
 * CollaborativeWorkflowDiagram EditorPreferences Integration Tests
 *
 * Tests the integration of EditorPreferencesStore with
 * CollaborativeWorkflowDiagram for history panel collapsed state
 * persistence.
 */

import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import type React from 'react';
import { describe, expect, test, beforeEach, afterEach, vi } from 'vitest';
import { CollaborativeWorkflowDiagram } from '../../../../js/collaborative-editor/components/diagram/CollaborativeWorkflowDiagram';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import type { StoreContextValue } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { createEditorPreferencesStore } from '../../../../js/collaborative-editor/stores/createEditorPreferencesStore';
import type { EditorPreferencesStore } from '../../../../js/collaborative-editor/types/editorPreferences';
import * as storage from 'lib0/storage';

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
  editorPreferencesStore: EditorPreferencesStore
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
  const historyState = {
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
    runStore: {} as any,
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
    test('auto-expands history panel when URL contains run ID', async () => {
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

      // Should auto-expand despite stored collapsed state
      await waitFor(() => {
        expect(screen.getByText(/Recent History/i)).toBeInTheDocument();
      });

      // Storage should be updated
      const stored = storage.varStorage.getItem(
        'lightning.editor.historyPanelCollapsed'
      );
      expect(stored).toBe('false');
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
});
