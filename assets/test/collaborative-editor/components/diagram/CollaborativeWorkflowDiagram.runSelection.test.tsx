import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import * as storage from 'lib0/storage';
import type React from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { CollaborativeWorkflowDiagram } from '../../../../js/collaborative-editor/components/diagram/CollaborativeWorkflowDiagram';
import type { StoreContextValue } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { KeyboardProvider } from '../../../../js/collaborative-editor/keyboard';
import { createEditorPreferencesStore } from '../../../../js/collaborative-editor/stores/createEditorPreferencesStore';
import {
  createMockURLState,
  getURLStateMockValue,
} from '../../__helpers__/urlStateMocks';

const LIVE_SNAPSHOT = 'snapshot-live';
const OLD_SNAPSHOT = 'snapshot-old';

function createWithSelectorMock(getSnapshot: () => unknown) {
  return function (selector: (state: never) => unknown) {
    let lastResult: unknown;
    let lastState: unknown;
    return function (): unknown {
      const currentState = getSnapshot();
      if (currentState !== lastState) {
        lastResult = selector(currentState as never);
        lastState = currentState;
      }
      return lastResult;
    };
  };
}

const urlState = createMockURLState();

vi.mock('../../../../js/collaborative-editor/hooks/useWorkflow', async () => ({
  ...(await vi.importActual<
    typeof import('../../../../js/collaborative-editor/hooks/useWorkflow')
  >('../../../../js/collaborative-editor/hooks/useWorkflow')),
  useWorkflowActions: () => ({ saveWorkflow: vi.fn() }),
}));

vi.mock('../../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: () => ({ isSynced: true, settled: true }),
}));

vi.mock('../../../../js/collaborative-editor/hooks/useUnsavedChanges', () => ({
  useUnsavedChanges: () => ({ hasChanges: false }),
}));

vi.mock('../../../../js/react/lib/use-url-state', () => ({
  useURLState: () => getURLStateMockValue(urlState),
}));

vi.mock('@xyflow/react', () => ({
  ReactFlow: () => <div data-testid="react-flow">Workflow Diagram</div>,
  ReactFlowProvider: ({ children }: { children: React.ReactNode }) => (
    <div>{children}</div>
  ),
  Background: () => null,
  Controls: () => null,
  MiniMap: () => null,
  useReactFlow: () => ({ fitView: vi.fn() }),
}));

vi.mock(
  '../../../../js/collaborative-editor/components/diagram/WorkflowDiagram',
  () => ({
    default: () => <div data-testid="workflow-diagram-impl" />,
  })
);

vi.mock('../../../../js/hooks', () => ({ relativeLocale: {} }));

vi.mock('date-fns', async () => {
  const actual = await vi.importActual('date-fns');
  return { ...actual, formatRelative: vi.fn(() => '2 hours ago') };
});

const run = (id: string, snapshotId: string | null) => ({
  id,
  state: 'success' as const,
  error_type: null,
  started_at: '2026-09-09T21:13:00Z',
  finished_at: '2026-09-09T21:13:01Z',
  version: 1,
  version_number: null,
  snapshot_id: snapshotId,
});

const workOrder = (id: string, runs: ReturnType<typeof run>[]) => ({
  id,
  state: 'success' as const,
  last_activity: '2026-09-09T21:13:01Z',
  runs,
});

function createWrapper(
  experimentalFeaturesEnabled = true,
  contentLocked = true
): React.ComponentType<{ children: React.ReactNode }> {
  const editorPreferencesStore = createEditorPreferencesStore();

  const workflowState = {
    workflow: { jobs: [], triggers: [], edges: [], lock_version: 1 },
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
    latestSnapshotId: LIVE_SNAPSHOT,
    latestSnapshotLockVersion: 3,
    experimentalFeaturesEnabled,
    contentLocked,
  };

  const historyState = {
    history: [
      workOrder('wo-old-a', [run('run-old-a', OLD_SNAPSHOT)]),
      workOrder('wo-old-b', [run('run-old-b', OLD_SNAPSHOT)]),
      workOrder('wo-live', [run('run-live', LIVE_SNAPSHOT)]),
      workOrder('wo-unknown', [run('run-unknown', null)]),
      workOrder('wo-current', [
        { ...run('run-current', LIVE_SNAPSHOT), version: 3 },
      ]),
    ],
    loading: false,
    error: null,
    channelConnected: false,
    activeRun: null,
    runStepsCache: {},
    runStepsSubscribers: {},
    runStepsLoading: new Set(),
  };

  const workflowGetSnapshot = () => workflowState;
  const sessionGetSnapshot = () => sessionState;
  const historyGetSnapshot = () => historyState;

  const mockStoreValue: StoreContextValue = {
    editorPreferencesStore,
    adaptorStore: {} as never,
    credentialStore: {} as never,
    awarenessStore: {} as never,
    workflowStore: {
      getSnapshot: workflowGetSnapshot,
      subscribe: () => () => {},
      withSelector: createWithSelectorMock(workflowGetSnapshot),
      selectNode: () => {},
    } as never,
    sessionContextStore: {
      getSnapshot: sessionGetSnapshot,
      subscribe: () => () => {},
      withSelector: createWithSelectorMock(sessionGetSnapshot),
    } as never,
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
    } as never,
    uiStore: {} as never,
    metadataStore: {} as never,
    aiAssistantStore: {} as never,
  };

  return ({ children }: { children: React.ReactNode }) => (
    <KeyboardProvider>
      <StoreContext.Provider value={mockStoreValue}>
        {children}
      </StoreContext.Provider>
    </KeyboardProvider>
  );
}

const clickRun = async (
  user: ReturnType<typeof userEvent.setup>,
  workOrderId: string
) => {
  await user.click(screen.getByTestId(`work-order-${workOrderId}`));
};

describe('selecting a run', () => {
  beforeEach(() => {
    Object.keys(storage.varStorage).forEach(key =>
      storage.varStorage.removeItem(key)
    );
    urlState.reset();
  });

  test('opens a run of older content as it executed', async () => {
    const user = userEvent.setup();
    render(<CollaborativeWorkflowDiagram />, { wrapper: createWrapper() });

    await clickRun(user, 'wo-old-a');

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith(
      expect.objectContaining({ as_run: 'run-old-a', run: 'run-old-a' })
    );
  });

  test('gives the same answer whichever view you click from', async () => {
    const user = userEvent.setup();
    render(<CollaborativeWorkflowDiagram />, { wrapper: createWrapper() });

    await clickRun(user, 'wo-old-a');

    urlState.setParam('as_run', 'run-old-a');
    urlState.setParam('run', 'run-old-a');
    urlState.mockFns.updateSearchParams.mockClear();

    await clickRun(user, 'wo-old-b');

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith(
      expect.objectContaining({ as_run: 'run-old-b' })
    );
    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalledWith(
      expect.objectContaining({ as_run: null })
    );
  });

  test('keeps you on the live document for a run of the live content', async () => {
    const user = userEvent.setup();
    render(<CollaborativeWorkflowDiagram />, { wrapper: createWrapper() });

    await clickRun(user, 'wo-live');

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith(
      expect.objectContaining({ as_run: null, run: 'run-live', v: null })
    );
  });

  test('keeps a retry on the live document when it drops the run view', async () => {
    const user = userEvent.setup();

    urlState.setParams({ run: 'run-old-a', as_run: 'run-old-a' });

    const { rerender } = render(<CollaborativeWorkflowDiagram />, {
      wrapper: createWrapper(),
    });

    urlState.deleteParam('as_run');
    urlState.setParams({ run: 'run-live' });
    urlState.mockFns.updateSearchParams.mockClear();
    rerender(<CollaborativeWorkflowDiagram />);

    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalledWith(
      expect.objectContaining({ run: null })
    );
  });

  test('shows a run as executed even when the URL only says ?run=', async () => {
    urlState.setParams({ run: 'run-old-a' });

    render(<CollaborativeWorkflowDiagram />, { wrapper: createWrapper() });

    await waitFor(() => {
      expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith(
        expect.objectContaining({ as_run: 'run-old-a' })
      );
    });
  });

  test("pins the run's own snapshot without experimental features", async () => {
    const user = userEvent.setup();
    render(<CollaborativeWorkflowDiagram />, {
      wrapper: createWrapper(false),
    });

    await clickRun(user, 'wo-old-a');

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      v: '1',
      run: 'run-old-a',
    });
    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalledWith(
      expect.objectContaining({ as_run: 'run-old-a' })
    );
  });

  test('clears the pin for a run of the current version, without the flag', async () => {
    const user = userEvent.setup();
    urlState.setParams({ v: '1' });

    render(<CollaborativeWorkflowDiagram />, { wrapper: createWrapper(false) });

    await clickRun(user, 'wo-current');

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      v: null,
      run: 'run-current',
    });
  });

  test('leaves a ?run= alone without experimental features', async () => {
    urlState.setParams({ run: 'run-old-a' });

    render(<CollaborativeWorkflowDiagram />, {
      wrapper: createWrapper(false),
    });

    await waitFor(() => {
      expect(screen.getByTestId('workflow-diagram-impl')).toBeInTheDocument();
    });

    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalledWith(
      expect.objectContaining({ as_run: 'run-old-a' })
    );
  });

  test('shows a run as executed when its snapshot is unknown', async () => {
    const user = userEvent.setup();
    render(<CollaborativeWorkflowDiagram />, { wrapper: createWrapper() });

    await clickRun(user, 'wo-unknown');

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith(
      expect.objectContaining({ as_run: 'run-unknown' })
    );
  });
});
