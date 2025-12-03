/**
 * FullScreenIDE Component Tests
 *
 * Tests the FullScreenIDE component state machine for the right panel:
 * - Landing state (initial): Two buttons - "View History" and "Create Run"
 * - Create-run state: ManualRunPanel with input selection
 * - History state: MiniHistory with run list
 * - Run-viewer state: RunViewerPanel with loaded run
 *
 * Also tests:
 * - Run button disabled states based on panel state
 * - Job switching behavior
 * - Keyboard shortcuts
 */

import { StoreProvider } from '#/collaborative-editor/contexts/StoreProvider';
import { KeyboardProvider } from '#/collaborative-editor/keyboard';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import * as Y from 'yjs';
import * as dataclipApi from '../../../../js/collaborative-editor/api/dataclips';
import { FullScreenIDE } from '../../../../js/collaborative-editor/components/ide/FullScreenIDE';
import type { Workflow } from '../../../../js/collaborative-editor/types/workflow';

// Mock dependencies
vi.mock('../../../../js/collaborative-editor/api/dataclips');

// Mock MonacoEditor
vi.mock('@monaco-editor/react', () => ({
  default: ({ value }: { value: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
}));

vi.mock('../../../../js/monaco', () => ({
  MonacoEditor: ({ value }: { value?: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
  setTheme: vi.fn(),
}));

// Mock tab panel components
vi.mock(
  '../../../../js/collaborative-editor/components/run-viewer/RunTabPanel',
  () => ({
    RunTabPanel: () => <div>Run Tab Content</div>,
  })
);

vi.mock(
  '../../../../js/collaborative-editor/components/run-viewer/LogTabPanel',
  () => ({
    LogTabPanel: () => <div>Log Tab Content</div>,
  })
);

vi.mock(
  '../../../../js/collaborative-editor/components/run-viewer/InputTabPanel',
  () => ({
    InputTabPanel: () => <div>Input Tab Content</div>,
  })
);

vi.mock(
  '../../../../js/collaborative-editor/components/run-viewer/OutputTabPanel',
  () => ({
    OutputTabPanel: () => <div>Output Tab Content</div>,
  })
);

// Mock CollaborativeMonaco
vi.mock(
  '../../../../js/collaborative-editor/components/CollaborativeMonaco',
  () => ({
    CollaborativeMonaco: () => (
      <div data-testid="collaborative-monaco">Monaco Editor</div>
    ),
  })
);

// Mock ManualRunPanel
vi.mock(
  '../../../../js/collaborative-editor/components/ManualRunPanel',
  () => ({
    ManualRunPanel: ({ renderMode }: { renderMode?: string }) => (
      <div data-testid="manual-run-panel" data-render-mode={renderMode}>
        ManualRunPanel (renderMode: {renderMode || 'standalone'})
      </div>
    ),
  })
);

// Mock MiniHistory
vi.mock(
  '../../../../js/collaborative-editor/components/diagram/MiniHistory',
  () => ({
    default: ({
      onBack,
      selectRunHandler,
    }: {
      onBack?: () => void;
      selectRunHandler?: (run: { id: string }) => void;
    }) => (
      <div data-testid="mini-history">
        MiniHistory
        {onBack && (
          <button data-testid="mini-history-back" onClick={onBack}>
            Back
          </button>
        )}
        {selectRunHandler && (
          <button
            data-testid="select-run-btn"
            onClick={() => selectRunHandler({ id: 'run-1' })}
          >
            Select Run
          </button>
        )}
      </div>
    ),
  })
);

// Mock RunViewerPanel
vi.mock(
  '../../../../js/collaborative-editor/components/run-viewer/RunViewerPanel',
  () => ({
    RunViewerPanel: ({ followRunId }: { followRunId: string }) => (
      <div data-testid="run-viewer-panel">RunViewerPanel - {followRunId}</div>
    ),
  })
);

// Mock useURLState hook
let mockSearchParams = new URLSearchParams();
const mockUpdateSearchParams = vi.fn(
  (params: Record<string, string | null>) => {
    Object.entries(params).forEach(([key, value]) => {
      if (value === null) {
        mockSearchParams.delete(key);
      } else {
        mockSearchParams.set(key, value);
      }
    });
  }
);

vi.mock('../../../../js/react/lib/use-url-state', () => ({
  useURLState: () => ({
    searchParams: mockSearchParams,
    updateSearchParams: mockUpdateSearchParams,
    hash: '',
  }),
}));

// Mock session hooks
vi.mock('../../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: () => ({
    awareness: {
      setLocalStateField: vi.fn(),
      getStates: () => new Map(),
    },
  }),
}));

vi.mock('../../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useProject: () => ({
    id: 'project-1',
    name: 'Test Project',
  }),
  useProjectRepoConnection: () => undefined,
  useLatestSnapshotLockVersion: () => 1,
  useIsNewWorkflow: () => false,
  useUser: () => ({
    id: 'user-1',
    first_name: 'Test',
    last_name: 'User',
    email: 'test@example.com',
  }),
  useAppConfig: () => ({
    ai_enabled: false,
  }),
  useVersions: () => [],
  useVersionsLoading: () => false,
  useVersionsError: () => null,
  useRequestVersions: () => vi.fn(),
}));

// Mock workflow hooks
const mockWorkflow: Workflow = {
  id: 'workflow-1',
  name: 'Test Workflow',
  jobs: [
    {
      id: 'job-1',
      name: 'Test Job',
      adaptor: '@openfn/language-http@latest',
      body: 'fn(state => state)',
      enabled: true,
      project_credential_id: null,
      keychain_credential_id: null,
    },
    {
      id: 'job-2',
      name: 'Second Job',
      adaptor: '@openfn/language-http@latest',
      body: 'fn(state => state)',
      enabled: true,
      project_credential_id: null,
      keychain_credential_id: null,
    },
  ],
  triggers: [
    {
      id: 'trigger-1',
      type: 'webhook',
      enabled: true,
    },
  ],
  edges: [],
};

const mockYText = new Y.Text();
mockYText.insert(0, 'fn(state => state)');

vi.mock('../../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useCanSave: () => ({
    canSave: true,
    tooltipMessage: 'Save workflow',
  }),
  useCanRun: () => ({
    canRun: true,
    tooltipMessage: 'Run workflow',
  }),
  useWorkflowReadOnly: () => ({
    isReadOnly: false,
    tooltipMessage: '',
  }),
  useWorkflowSettingsErrors: () => ({
    hasErrors: false,
    errors: [],
  }),
  useCurrentJob: () => ({
    job: mockWorkflow.jobs[0],
    ytext: mockYText,
  }),
  useNodeSelection: () => ({
    currentNode: { node: null, type: null, id: null },
    selectNode: vi.fn(),
  }),
  useWorkflowEnabled: () => ({
    enabled: true,
    setEnabled: vi.fn(),
  }),
  useWorkflowActions: () => ({
    selectJob: vi.fn(),
    saveWorkflow: vi.fn(),
    updateJob: vi.fn(),
  }),
  useWorkflowState: (selector: any) => {
    const state = {
      workflow: mockWorkflow,
      jobs: mockWorkflow.jobs,
      triggers: mockWorkflow.triggers,
      edges: mockWorkflow.edges,
      positions: {},
    };
    return typeof selector === 'function' ? selector(state) : state;
  },
}));

// Mock useRun hooks
vi.mock('../../../../js/collaborative-editor/hooks/useRun', () => ({
  useRunStoreInstance: () => ({
    getState: vi.fn(() => ({
      run: null,
      loading: false,
      error: null,
    })),
    subscribe: vi.fn(),
    setState: vi.fn(),
    _connectToRun: vi.fn(() => vi.fn()),
    _disconnectFromRun: vi.fn(),
  }),
  useRunActions: () => ({
    selectStep: vi.fn(),
  }),
  useCurrentRun: () => null,
}));

// Mock useHistory hooks
const mockSelectStep = vi.fn();
const mockRequestHistory = vi.fn();
const mockClearError = vi.fn();

vi.mock('../../../../js/collaborative-editor/hooks/useHistory', () => ({
  useFollowRun: vi.fn(() => ({ run: null, clearRun: vi.fn() })),
  useHistory: () => [],
  useHistoryLoading: () => false,
  useHistoryError: () => null,
  useHistoryCommands: () => ({
    selectStep: mockSelectStep,
    requestHistory: mockRequestHistory,
    requestRunSteps: vi.fn(),
    getRunSteps: vi.fn(),
    clearError: mockClearError,
    clearActiveRunError: vi.fn(),
  }),
  useJobMatchesRun: () => true,
  useActiveRun: () => null,
  useSelectedStepId: () => null,
}));

// Mock credential hooks
vi.mock('../../../../js/collaborative-editor/hooks/useCredentials', () => ({
  useCredentials: () => ({
    projectCredentials: [],
    keychainCredentials: [],
  }),
  useCredentialsCommands: () => ({
    requestCredentials: vi.fn(),
  }),
  useCredentialQueries: () => ({
    findCredentialById: vi.fn(),
    credentialExists: vi.fn(),
    getCredentialId: vi.fn(),
  }),
}));

// Mock adaptor hooks
vi.mock('../../../../js/collaborative-editor/hooks/useAdaptors', () => ({
  useProjectAdaptors: () => ({
    projectAdaptors: [],
    allAdaptors: [],
  }),
}));

// Mock LiveView actions
vi.mock(
  '../../../../js/collaborative-editor/contexts/LiveViewActionsContext',
  () => ({
    useLiveViewActions: () => ({
      pushEvent: vi.fn(),
      handleEvent: vi.fn(() => () => {}),
    }),
  })
);

// Mock adaptor modals
vi.mock(
  '../../../../js/collaborative-editor/components/ConfigureAdaptorModal',
  () => ({
    ConfigureAdaptorModal: () => <div data-testid="configure-adaptor-modal" />,
  })
);

vi.mock(
  '../../../../js/collaborative-editor/components/AdaptorSelectionModal',
  () => ({
    AdaptorSelectionModal: () => <div data-testid="adaptor-selection-modal" />,
  })
);

// Mock UI commands
vi.mock('../../../../js/collaborative-editor/hooks/useUI', () => ({
  useUICommands: () => ({
    openGitHubSyncModal: vi.fn(),
    openRunPanel: vi.fn(),
    closeRunPanel: vi.fn(),
  }),
  useIsRunPanelOpen: () => false,
  useIsGitHubSyncModalOpen: () => false,
  useRunPanelContext: () => null,
}));

// Mock GitHubSyncModal
vi.mock(
  '../../../../js/collaborative-editor/components/GitHubSyncModal',
  () => ({
    GitHubSyncModal: () => null,
  })
);

// Mock ActiveCollaborators
vi.mock(
  '../../../../js/collaborative-editor/components/ActiveCollaborators',
  () => ({
    ActiveCollaborators: () => <div data-testid="active-collaborators" />,
  })
);

// Mock run retry hooks
vi.mock('../../../../js/collaborative-editor/hooks/useRunRetry', () => ({
  useRunRetry: () => ({
    handleRun: vi.fn(),
    handleRetry: vi.fn(),
    isRetryable: false,
    runIsProcessing: false,
    runTooltipMessage: '',
    isSubmitting: false,
    canRun: true,
  }),
}));

vi.mock(
  '../../../../js/collaborative-editor/hooks/useRunRetryShortcuts',
  () => ({
    useRunRetryShortcuts: vi.fn(),
  })
);

// Mock version select hook
vi.mock('../../../../js/collaborative-editor/hooks/useVersionSelect', () => ({
  useVersionSelect: () => vi.fn(),
}));

// Mock JobSelector
vi.mock('../../../../js/collaborative-editor/components/JobSelector', () => ({
  JobSelector: ({
    currentJob,
    jobs,
    onChange,
  }: {
    currentJob: any;
    jobs: any[];
    onChange: (job: any) => void;
  }) => (
    <div data-testid="job-selector">
      <span data-testid="current-job-name">{currentJob.name}</span>
      <select
        data-testid="job-select"
        value={currentJob.id}
        onChange={e => {
          const selectedJob = jobs.find(j => j.id === e.target.value);
          if (selectedJob) onChange(selectedJob);
        }}
      >
        {jobs.map(job => (
          <option key={job.id} value={job.id}>
            {job.name}
          </option>
        ))}
      </select>
    </div>
  ),
}));

// Mock react-resizable-panels
vi.mock('react-resizable-panels', () => ({
  Panel: ({ children }: any) => {
    return <div data-testid="panel">{children}</div>;
  },
  PanelGroup: ({ children }: any) => (
    <div data-testid="panel-group">{children}</div>
  ),
  PanelResizeHandle: () => <div data-testid="resize-handle" />,
}));

// Helper function to render FullScreenIDE with providers
function renderFullScreenIDE(
  props: React.ComponentProps<typeof FullScreenIDE>
) {
  return render(
    <KeyboardProvider>
      <StoreProvider>
        <FullScreenIDE {...props} />
      </StoreProvider>
    </KeyboardProvider>
  );
}

describe('FullScreenIDE', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    // Default mock for searchDataclips
    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [],
      next_cron_run_dataclip_id: null,
      can_edit_dataclip: true,
    });

    // Reset search params to default state
    mockSearchParams = new URLSearchParams();
    mockSearchParams.set('job', 'job-1');
  });

  describe('Initial Landing State', () => {
    test('displays landing panel with View History and Create Run buttons', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('View History')).toBeInTheDocument();
        expect(screen.getByText('Create Run')).toBeInTheDocument();
      });
    });

    test('Run button is disabled in landing state', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('View History')).toBeInTheDocument();
      });

      // Run button should be disabled in landing state
      // Use exact match to avoid matching "Create Run" button
      const runButton = screen.getByRole('button', { name: 'Run' });
      expect(runButton).toBeDisabled();
    });

    test('shows "Runs" label in right panel header when in landing state', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('Runs')).toBeInTheDocument();
      });
    });
  });

  describe('Landing → Create Run Flow', () => {
    test('clicking Create Run shows ManualRunPanel', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('Create Run')).toBeInTheDocument();
      });

      // Click Create Run
      await user.click(screen.getByText('Create Run'));

      // Should now show ManualRunPanel
      await waitFor(() => {
        expect(screen.getByTestId('manual-run-panel')).toBeInTheDocument();
      });
    });

    test('Run button is enabled in create-run state', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('Create Run')).toBeInTheDocument();
      });

      // Click Create Run
      await user.click(screen.getByText('Create Run'));

      await waitFor(() => {
        expect(screen.getByTestId('manual-run-panel')).toBeInTheDocument();
      });

      // Run button should be enabled
      const runButton = screen.getByRole('button', { name: 'Run' });
      expect(runButton).not.toBeDisabled();
    });

    test('shows back button that returns to landing state', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('Create Run')).toBeInTheDocument();
      });

      // Click Create Run
      await user.click(screen.getByText('Create Run'));

      await waitFor(() => {
        expect(screen.getByTestId('manual-run-panel')).toBeInTheDocument();
      });

      // Click back button
      const backButton = screen.getByLabelText('Back to landing');
      await user.click(backButton);

      // Should be back at landing
      await waitFor(() => {
        expect(screen.getByText('View History')).toBeInTheDocument();
        expect(screen.getByText('Create Run')).toBeInTheDocument();
      });

      // Run button should be disabled again
      const runButton = screen.getByRole('button', { name: 'Run' });
      expect(runButton).toBeDisabled();
    });
  });

  describe('Landing → History Flow', () => {
    test('clicking View History shows MiniHistory', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('View History')).toBeInTheDocument();
      });

      // Click View History
      await user.click(screen.getByText('View History'));

      // Should now show MiniHistory
      await waitFor(() => {
        expect(screen.getByTestId('mini-history')).toBeInTheDocument();
      });

      // Should have requested history
      expect(mockRequestHistory).toHaveBeenCalled();
    });

    test('Run button stays disabled in history state', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('View History')).toBeInTheDocument();
      });

      // Click View History
      await user.click(screen.getByText('View History'));

      await waitFor(() => {
        expect(screen.getByTestId('mini-history')).toBeInTheDocument();
      });

      // Run button should still be disabled
      const runButton = screen.getByRole('button', { name: 'Run' });
      expect(runButton).toBeDisabled();
    });

    test('back button returns to landing from history', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('View History')).toBeInTheDocument();
      });

      // Click View History
      await user.click(screen.getByText('View History'));

      await waitFor(() => {
        expect(screen.getByTestId('mini-history')).toBeInTheDocument();
      });

      // Click back button
      const backButton = screen.getByTestId('mini-history-back');
      await user.click(backButton);

      // Should be back at landing
      await waitFor(() => {
        expect(screen.getByText('View History')).toBeInTheDocument();
        expect(screen.getByText('Create Run')).toBeInTheDocument();
      });
    });
  });

  describe('Header and Layout', () => {
    test('displays job name in header', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        const jobNames = screen.getAllByText(/Test Job/i);
        expect(jobNames.length).toBeGreaterThan(0);
      });
    });

    test('displays Code panel with job name', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText(/Code -/i)).toBeInTheDocument();
      });
    });

    test('displays Close IDE button', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByLabelText('Close IDE')).toBeInTheDocument();
      });
    });

    test('clicking close button calls onClose', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByLabelText('Close IDE')).toBeInTheDocument();
      });

      await user.click(screen.getByLabelText('Close IDE'));

      expect(onClose).toHaveBeenCalledOnce();
    });

    test('displays CollaborativeMonaco editor', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument();
      });
    });
  });

  describe('Keyboard Shortcuts', () => {
    test('Escape key eventually calls onClose', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument();
      });

      // Press Escape twice (first may blur Monaco, second closes)
      await user.keyboard('{Escape}');
      await user.keyboard('{Escape}');

      expect(onClose).toHaveBeenCalled();
    });
  });

  describe('Panel Layout', () => {
    test('renders panel groups', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        const panelGroups = screen.getAllByTestId('panel-group');
        expect(panelGroups.length).toBeGreaterThanOrEqual(1);
      });
    });

    test('has collapse buttons for panels', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('View History')).toBeInTheDocument();
      });

      const collapseButtons = screen.getAllByRole('button', {
        name: /collapse/i,
      });
      expect(collapseButtons.length).toBeGreaterThan(0);
    });
  });
});
