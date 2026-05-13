/**
 * Tests for CollaborativeWorkflowDiagram URL fallback behavior.
 *
 * When a run is selected, the run ID is stored both in the URL (?run=...)
 * and in the history store (activeRunId). LiveView push_patch can strip
 * the client-side 'run' URL param because build_url only knows about
 * server-managed params. The diagram must:
 *
 * 1. Fall back to activeRunId when the URL param is missing
 * 2. Restore the URL param when it gets stripped but activeRunId persists
 *
 * These tests verify that behavior at the component level.
 */

import { render, waitFor } from '@testing-library/react';
import * as storage from 'lib0/storage';
import type React from 'react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { CollaborativeWorkflowDiagram } from '../../../../js/collaborative-editor/components/diagram/CollaborativeWorkflowDiagram';
import type { StoreContextValue } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { KeyboardProvider } from '../../../../js/collaborative-editor/keyboard';
import { createEditorPreferencesStore } from '../../../../js/collaborative-editor/stores/createEditorPreferencesStore';
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

// Mock ReactFlow
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

// Track the activeRun for the history store mock
let mockActiveRunId: string | null = null;

function createWrapper(
  historyStateOverride?: any
): React.ComponentType<{ children: React.ReactNode }> {
  const editorPreferencesStore = createEditorPreferencesStore();

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
    activeRun: mockActiveRunId ? { id: mockActiveRunId } : null,
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
      _viewRun: vi.fn(),
      _closeRunViewer: vi.fn(),
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

describe('CollaborativeWorkflowDiagram - URL fallback for run param', () => {
  beforeEach(() => {
    storage.varStorage.clear?.() ||
      Object.keys(storage.varStorage).forEach(key =>
        storage.varStorage.removeItem(key)
      );

    urlState.reset();
    mockActiveRunId = null;
  });

  afterEach(() => {
    storage.varStorage.clear?.() ||
      Object.keys(storage.varStorage).forEach(key =>
        storage.varStorage.removeItem(key)
      );
  });

  test('renders without run param and no active run', () => {
    const wrapper = createWrapper();

    const { getByTestId } = render(<CollaborativeWorkflowDiagram />, {
      wrapper,
    });

    // Should render successfully
    expect(getByTestId('workflow-diagram-impl')).toBeInTheDocument();
    // Should NOT attempt to restore run param
    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalledWith(
      expect.objectContaining({ run: expect.any(String) })
    );
  });

  test('does not restore URL when run param is present', () => {
    urlState.setParam('run', 'run-123');
    mockActiveRunId = 'run-123';

    const wrapper = createWrapper();
    render(<CollaborativeWorkflowDiagram />, { wrapper });

    // Should NOT call updateSearchParams to restore (param is already there)
    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalledWith(
      expect.objectContaining({ run: 'run-123' })
    );
  });

  test('restores URL run param when stripped but activeRunId exists', async () => {
    // Simulate: URL param is missing but history store has active run
    // This happens when LiveView push_patch strips the client-side param
    mockActiveRunId = 'run-123';
    // No urlState.setParam('run', ...) — param is missing

    const wrapper = createWrapper();
    render(<CollaborativeWorkflowDiagram />, { wrapper });

    // The effect should restore the run param
    await waitFor(() => {
      expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
        run: 'run-123',
      });
    });
  });

  test('does not restore URL when both param and activeRunId are absent', () => {
    // No run param, no active run
    mockActiveRunId = null;

    const wrapper = createWrapper();
    render(<CollaborativeWorkflowDiagram />, { wrapper });

    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalledWith(
      expect.objectContaining({ run: expect.any(String) })
    );
  });

  test('only attempts one restore per activeRunId to prevent loops', async () => {
    // Simulate: LiveView keeps stripping the run param on every push_patch.
    // The component should restore the URL once but not keep retrying.
    mockActiveRunId = 'run-loop';

    const wrapper = createWrapper();
    const { rerender } = render(<CollaborativeWorkflowDiagram />, { wrapper });

    // First render: should restore the param
    await waitFor(() => {
      expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
        run: 'run-loop',
      });
    });

    urlState.mockFns.updateSearchParams.mockClear();

    // Simulate LiveView stripping the param again (re-render with no run param)
    // mockActiveRunId is still 'run-loop', runParam is still absent
    rerender(<CollaborativeWorkflowDiagram />);

    // Should NOT attempt a second restore for the same activeRunId
    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalledWith(
      expect.objectContaining({ run: 'run-loop' })
    );
  });
});
