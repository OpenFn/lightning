/**
 * CollaborativeEditor - "Build from scratch" landing screen flow
 *
 * Covers `LandingScreenWrapper`'s `runBuildFromScratch` handler
 * (CollaborativeEditor.tsx). `LandingScreenWrapper` is not exported, so this
 * mounts the full `CollaborativeEditor` tree with the same heavy-mock
 * pattern as `CollaborativeEditor.keyboard.test.tsx`, then interacts with
 * the real `LandingScreen` card.
 */

import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { CollaborativeEditor } from '../../../js/collaborative-editor/CollaborativeEditor';
import type { Workflow } from '../../../js/collaborative-editor/types/workflow';
import type { WorkflowState } from '../../../js/yaml/types';
import {
  createMockURLState,
  getURLStateMockValue,
} from '../__helpers__/urlStateMocks';

// --- Socket / channel plumbing (required for SocketProvider/SessionProvider to mount) ---

vi.mock('phoenix', () => ({
  Socket: vi.fn(() => ({
    connect: vi.fn(),
    disconnect: vi.fn(),
    channel: vi.fn(() => ({
      join: vi.fn(() => ({
        receive: vi.fn((status: string, callback: () => void) => {
          if (status === 'ok') callback();
          return { receive: vi.fn() };
        }),
      })),
      on: vi.fn(),
      push: vi.fn(() => ({
        receive: vi.fn(() => ({ receive: vi.fn() })),
      })),
      leave: vi.fn(),
    })),
    onError: vi.fn(),
  })),
}));

vi.mock('../../../js/collaborative-editor/api/dataclips', () => ({
  searchDataclips: vi.fn(() =>
    Promise.resolve({
      data: [],
      next_cron_run_dataclip_id: null,
      can_edit_dataclip: true,
    })
  ),
}));

vi.mock('@monaco-editor/react', () => ({
  default: ({ value }: { value: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
}));

// --- Heavy child components stubbed out — not under test here ---

vi.mock(
  '../../../js/collaborative-editor/components/diagram/CollaborativeWorkflowDiagram',
  () => ({
    CollaborativeWorkflowDiagram: () => (
      <div data-testid="workflow-diagram">Workflow Diagram</div>
    ),
  })
);

vi.mock('../../../js/collaborative-editor/components/inspector', () => ({
  Inspector: () => <div data-testid="inspector">Inspector</div>,
}));

vi.mock(
  '../../../js/collaborative-editor/components/ide/FullScreenIDE',
  () => ({
    FullScreenIDE: () => (
      <div data-testid="fullscreen-ide">Full Screen IDE</div>
    ),
  })
);

vi.mock('../../../js/collaborative-editor/components/ManualRunPanel', () => ({
  ManualRunPanel: () => (
    <div data-testid="manual-run-panel">ManualRunPanel</div>
  ),
}));

vi.mock(
  '../../../js/collaborative-editor/components/AIAssistantPanelWrapper',
  () => ({
    AIAssistantPanelWrapper: () => (
      <div data-testid="ai-assistant-panel-wrapper" />
    ),
  })
);

vi.mock('../../../js/collaborative-editor/components/ui/Toaster', () => ({
  Toaster: () => <div data-testid="toaster" />,
}));

vi.mock('../../../js/collaborative-editor/components/VersionDropdown', () => ({
  VersionDropdown: () => <div data-testid="version-dropdown" />,
}));

vi.mock(
  '../../../js/collaborative-editor/components/VersionDebugLogger',
  () => ({ VersionDebugLogger: () => null })
);

vi.mock('../../../js/collaborative-editor/components/LoadingBoundary', () => ({
  LoadingBoundary: ({ children }: { children: React.ReactNode }) => (
    <>{children}</>
  ),
}));

vi.mock(
  '../../../js/collaborative-editor/contexts/CredentialModalContext',
  () => ({
    CredentialModalProvider: ({ children }: { children: React.ReactNode }) =>
      children,
    useCredentialModal: () => ({
      openCredentialModal: vi.fn(),
      isCredentialModalOpen: false,
      onModalClose: vi.fn(() => vi.fn()),
      onCredentialSaved: vi.fn(() => vi.fn()),
    }),
  })
);

// YAML import / template browser also render inside LandingScreenWrapper
// whenever the landing screen is shown — stub them out, they're covered by
// their own test suites.
vi.mock('../../../js/collaborative-editor/components/YAMLImportModal', () => ({
  YAMLImportModal: () => <div data-testid="yaml-import-modal-stub" />,
}));

vi.mock(
  '../../../js/collaborative-editor/components/TemplateBrowserModalWrapper',
  () => ({
    TemplateBrowserModalWrapper: () => (
      <div data-testid="template-browser-modal-stub" />
    ),
  })
);

// --- Session context ---

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useIsNewWorkflow: () => false,
  useProjectRepoConnection: () => undefined,
  useProject: () => ({ id: 'project-1', name: 'Test Project' }),
  useVersions: () => [],
  useVersionsLoading: () => false,
  useVersionsError: () => null,
  useRequestVersions: () => vi.fn(),
  useLatestSnapshotLockVersion: () => 1,
  useUser: () => ({
    id: 'user-1',
    email: 'test@example.com',
    email_confirmed_at: new Date().toISOString(),
  }),
  useAppConfig: () => ({ email_verification_enabled: false }),
  useLimits: () => ({
    runs: { allowed: true, message: null },
    workflow_activation: { allowed: true, message: null },
    github_sync: { allowed: true, message: null },
  }),
  useSessionContext: () => ({
    workflow: { jobs: [], triggers: [], edges: [], name: 'wf', positions: {} },
  }),
}));

// --- Workflow store / actions — the core of this flow ---

const mockWorkflow: Workflow = {
  id: 'workflow-1',
  name: 'Test Workflow',
  jobs: [],
  triggers: [{ id: 'trigger-1', type: 'webhook', enabled: true }],
  edges: [],
};

const mockImportWorkflow = vi.fn().mockResolvedValue(undefined);
const mockSaveWorkflow = vi.fn().mockResolvedValue({ ok: true });

// `useCreateWorkflowFlow` (used by `LandingScreenWrapper`) is re-implemented
// here rather than mocked-through, since it lives in the same module as
// `useWorkflowActions` below and a vi.mock override of one export can't
// reach an internal same-module call to the other. This mirrors the real
// hook's gate/import/save sequence exactly (see useWorkflow.tsx), driven by
// the same mockIsConnected/mockImportWorkflow/mockSaveWorkflow the rest of
// this suite already controls.
vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useCreateWorkflowFlow: () => ({
    createWorkflowFrom: async (buildState: () => unknown) => {
      if (!mockIsConnected) {
        mockAlert({
          title: 'Not connected',
          description: 'Connect to the server before creating a workflow.',
        });
        return false;
      }
      try {
        const state = buildState();
        await mockImportWorkflow(state);
      } catch {
        mockAlert({
          title: 'Failed to create workflow',
          description: 'Please check your connection and try again.',
        });
        return false;
      }
      try {
        await mockSaveWorkflow({ notify: 'error-only' });
      } catch {
        return false;
      }
      return true;
    },
  }),
  useNodeSelection: () => ({
    currentNode: { type: null, node: null },
    selectNode: vi.fn(),
  }),
  useWorkflowStoreContext: () => ({
    getSnapshot: vi.fn(() => ({ triggers: [] })),
    subscribe: vi.fn(() => vi.fn()),
    removeEdge: vi.fn(),
    removeJob: vi.fn(),
    clearAllTriggers: vi.fn(),
  }),
  useWorkflowActions: () => ({
    importWorkflow: mockImportWorkflow,
    saveWorkflow: mockSaveWorkflow,
  }),
  useWorkflowState: (selector?: (state: unknown) => unknown) => {
    const state = {
      workflow: mockWorkflow,
      jobs: mockWorkflow.jobs,
      triggers: mockWorkflow.triggers,
      edges: mockWorkflow.edges,
      positions: {},
    };
    return typeof selector === 'function' ? selector(state) : state;
  },
  useCanRun: () => ({ canRun: true, tooltipMessage: '' }),
  useWorkflowEnabled: () => ({ enabled: true, setEnabled: vi.fn() }),
  useCanSave: () => ({ canSave: true, tooltipMessage: '' }),
  useWorkflowSettingsErrors: () => ({ hasErrors: false, errors: [] }),
  useWorkflowReadOnly: () => ({ isReadOnly: false, tooltipMessage: '' }),
}));

// --- UI store ---

const mockShowLandingScreen = vi.fn(() => true);
const mockDismissLandingScreen = vi.fn();
const mockOpenAIAssistantPanel = vi.fn();
const mockOpenYAMLImportModal = vi.fn();
const mockOpenTemplateBrowserModal = vi.fn();

vi.mock('../../../js/collaborative-editor/hooks/useUI', () => ({
  useIsRunPanelOpen: () => false,
  useRunPanelContext: () => null,
  useIsAIAssistantPanelOpen: () => false,
  useAIAssistantInitialMessage: () => null,
  useIsGitHubSyncModalOpen: () => false,
  useIsCreateWorkflowPanelCollapsed: () => true,
  useShowLandingScreen: () => mockShowLandingScreen(),
  useImportPanelState: () => 'initial',
  useUICommands: () => ({
    openYAMLImportModal: mockOpenYAMLImportModal,
    openTemplateBrowserModal: mockOpenTemplateBrowserModal,
    dismissLandingScreen: mockDismissLandingScreen,
    openAIAssistantPanel: mockOpenAIAssistantPanel,
    openRunPanel: vi.fn(),
    closeRunPanel: vi.fn(),
    closeAIAssistantPanel: vi.fn(),
    toggleAIAssistantPanel: vi.fn(),
    openGitHubSyncModal: vi.fn(),
    closeGitHubSyncModal: vi.fn(),
    toggleCreateWorkflowPanel: vi.fn(),
    collapseCreateWorkflowPanel: vi.fn(),
    expandCreateWorkflowPanel: vi.fn(),
    selectTemplate: vi.fn(),
    setTemplateSearchQuery: vi.fn(),
  }),
  useTemplatePanel: () => ({
    templates: [],
    loading: false,
    searchQuery: '',
  }),
}));

// --- Notifications ---

const mockAlert = vi.fn();
vi.mock('../../../js/collaborative-editor/lib/notifications', () => ({
  notifications: {
    alert: (options: unknown) => {
      mockAlert(options);
    },
    info: vi.fn(),
    dismiss: vi.fn(),
  },
}));

// --- URL state ---

const urlState = createMockURLState();
vi.mock('../../../js/react/lib/use-url-state', () => ({
  useURLState: () => getURLStateMockValue(urlState),
}));

// --- Session (workflow-session socket connectivity) ---

let mockIsConnected = true;
vi.mock('../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: (selector?: (s: Record<string, unknown>) => unknown) => {
    const state = {
      provider: null,
      ydoc: null,
      awareness: null,
      isConnected: mockIsConnected,
      isSynced: false,
    };
    return typeof selector === 'function' ? selector(state) : state;
  },
}));

function renderEditor() {
  return render(
    <CollaborativeEditor
      data-workflow-id="workflow-1"
      data-workflow-name="Test Workflow"
      data-project-id="project-1"
      data-project-name="Test Project"
    />
  );
}

async function clickBuildFromScratch() {
  const card = await screen.findByTestId('build-from-scratch-card');
  fireEvent.click(card);
}

describe('CollaborativeEditor - Build from scratch', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    urlState.reset();
    mockShowLandingScreen.mockReturnValue(true);
    mockImportWorkflow.mockResolvedValue(undefined);
    mockSaveWorkflow.mockResolvedValue({ ok: true });
    mockIsConnected = true;
  });

  test('imports a webhook+job+edge blank workflow, saves it, and dismisses the landing screen', async () => {
    renderEditor();

    await clickBuildFromScratch();

    await waitFor(() =>
      expect(mockDismissLandingScreen).toHaveBeenCalledOnce()
    );

    expect(mockImportWorkflow).toHaveBeenCalledOnce();
    const importedState = mockImportWorkflow.mock
      .calls[0]?.[0] as WorkflowState;
    expect(importedState.triggers).toHaveLength(1);
    expect(importedState.triggers[0]).toMatchObject({ type: 'webhook' });
    expect(importedState.jobs).toHaveLength(1);
    expect(importedState.edges).toHaveLength(1);

    expect(mockSaveWorkflow).toHaveBeenCalledWith({ notify: 'error-only' });

    // Ordering: save → dismiss. Dismiss only fires once save has actually
    // succeeded.
    const saveOrder = mockSaveWorkflow.mock.invocationCallOrder[0];
    const dismissOrder = mockDismissLandingScreen.mock.invocationCallOrder[0];
    expect(saveOrder).toBeLessThan(dismissOrder);
  });

  test('offline gate: shows a "Not connected" alert and skips import when the session is disconnected', async () => {
    mockIsConnected = false;
    renderEditor();

    await clickBuildFromScratch();

    await waitFor(() =>
      expect(mockAlert).toHaveBeenCalledWith(
        expect.objectContaining({ title: 'Not connected' })
      )
    );

    expect(mockImportWorkflow).not.toHaveBeenCalled();
    expect(mockDismissLandingScreen).not.toHaveBeenCalled();
  });

  test('save failure: imports but does not dismiss the landing screen, and shows no bespoke alert', async () => {
    mockSaveWorkflow.mockRejectedValue(new Error('boom'));
    renderEditor();

    await clickBuildFromScratch();

    await waitFor(() => {
      expect(mockSaveWorkflow).toHaveBeenCalledWith({ notify: 'error-only' });
    });

    expect(mockImportWorkflow).toHaveBeenCalledOnce();
    expect(mockDismissLandingScreen).not.toHaveBeenCalled();
    // The shared save handler (mocked out via useWorkflowActions) owns the
    // Retry toast; this component shows no alert of its own for save failures.
    expect(mockAlert).not.toHaveBeenCalled();
  });

  test('shows a "Failed to create workflow" alert and keeps the landing screen open when importWorkflow throws', async () => {
    mockImportWorkflow.mockRejectedValue(new Error('channel error'));
    renderEditor();

    await clickBuildFromScratch();

    await waitFor(() =>
      expect(mockAlert).toHaveBeenCalledWith(
        expect.objectContaining({ title: 'Failed to create workflow' })
      )
    );

    expect(mockSaveWorkflow).not.toHaveBeenCalled();
    expect(mockDismissLandingScreen).not.toHaveBeenCalled();
  });

  test('double-clicking the card while a save is pending only runs the create flow once', async () => {
    const user = userEvent.setup();
    let resolveSave!: (value: { ok: boolean }) => void;
    mockSaveWorkflow.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveSave = resolve;
        })
    );

    renderEditor();
    const card = await screen.findByTestId('build-from-scratch-card');

    await user.click(card);
    expect(card).toBeDisabled();
    await user.click(card); // no-op: card is disabled while the first run is pending

    expect(mockImportWorkflow).toHaveBeenCalledOnce();
    expect(mockSaveWorkflow).toHaveBeenCalledOnce();

    resolveSave({ ok: true });
    await waitFor(() =>
      expect(mockDismissLandingScreen).toHaveBeenCalledOnce()
    );
    expect(card).not.toBeDisabled();
  });
});
