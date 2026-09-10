/**
 * Tests for how selecting a run decides what to show.
 *
 * A run is shown as it executed, on its own snapshot, unless it executed the
 * content that is live now, in which case it overlays on the live document so
 * editing carries on.
 *
 * The decision compares the run's snapshot against the live workflow's. It used
 * to compare version numbers against the document on screen, and because a run
 * view *is* a past document, the answer changed depending on where the user was
 * standing: clicking two runs of the same old content alternated between a
 * read-only view of that content and the live document with the run painted
 * onto it, which reported step timings against steps the run never touched.
 */

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
  useSession: () => ({ isSynced: true }),
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
  experimentalFeaturesEnabled = true
): React.ComponentType<{ children: React.ReactNode }> {
  const editorPreferencesStore = createEditorPreferencesStore();

  const workflowState = {
    // The document on screen. In a run view this is the run's snapshot, which
    // is exactly what the decision must not read.
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

    // Now standing in that run's view: the URL says so, and the document on
    // screen is that run's snapshot. Clicking a second run of the same content
    // used to compare against the displayed document, match, and drop the user
    // back onto the live document with the run painted over it.
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

    // Nothing to load: the run executed what is on screen, so editing carries
    // on and the steps light up where they ran.
    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith(
      expect.objectContaining({ as_run: null, run: 'run-live', v: null })
    );
  });

  test('keeps a retry on the live document when it drops the run view', async () => {
    const user = userEvent.setup();

    // Standing in a run's own view.
    urlState.setParams({ run: 'run-old-a', as_run: 'run-old-a' });

    const { rerender } = render(<CollaborativeWorkflowDiagram />, {
      wrapper: createWrapper(),
    });

    // A retry drops the run view and selects the run it just created, which
    // executed the live content. Reading that as "left the run view" cleared
    // the new run and left the canvas blank, with the retry sitting unselected
    // in the history list.
    urlState.deleteParam('as_run');
    urlState.setParams({ run: 'run-live' });
    urlState.mockFns.updateSearchParams.mockClear();
    rerender(<CollaborativeWorkflowDiagram />);

    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalledWith(
      expect.objectContaining({ run: null })
    );
  });

  test('shows a run as executed even when the URL only says ?run=', async () => {
    // A shared link, a reload, or the back button. The decision used to happen
    // only on click, so the address bar could still reach the old behaviour:
    // an old run's results painted on the live document.
    urlState.setParams({ run: 'run-old-a' });

    render(<CollaborativeWorkflowDiagram />, { wrapper: createWrapper() });

    await waitFor(() => {
      expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith(
        expect.objectContaining({ as_run: 'run-old-a' })
      );
    });
  });

  test("pins the run's own snapshot without experimental features", async () => {
    // The editor's existing behaviour: the run executed a different version, so
    // the canvas switches to that version, read-only. `?v=` numbers by
    // lock_version, which is what the run carries. No as-executed view is
    // involved; that is the flag-on answer.
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
    // The other half of main's rule, and the reason it exists: a run of the
    // current version must not leave the canvas pinned and read-only.
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
    // The reconcile pass turns a bare `?run=` of older content into an
    // as-executed view, however the URL got that way. Without the flag it must
    // leave the URL as it found it.
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

    // An older payload without the field. Read-only and faithful beats
    // editable and possibly wrong.
    await clickRun(user, 'wo-unknown');

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith(
      expect.objectContaining({ as_run: 'run-unknown' })
    );
  });
});
