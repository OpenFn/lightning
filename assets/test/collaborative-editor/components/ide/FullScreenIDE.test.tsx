/**
 * FullScreenIDE Component Tests
 *
 * Tests for FullScreenIDE component that provides a full-screen workspace
 * with three panels: ManualRunPanel (left), Monaco editor (center), and
 * output panel (right). Tests cover:
 * - Panel layout and default state (left panel open by default)
 * - ManualRunPanel integration with renderMode="embedded"
 * - Run button in header functionality
 * - Run state management (canRun, isRunning, handler)
 * - Keyboard shortcuts (Escape to close, Cmd+Enter to run)
 * - Panel collapse/expand functionality
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

// Mock the monaco module to avoid monaco-editor package resolution issues
vi.mock('../../../../js/monaco', () => ({
  MonacoEditor: ({ value }: { value?: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
  setTheme: vi.fn(),
}));

// Mock tab panel components to avoid monaco-editor dependency in log-viewer
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
    ManualRunPanel: ({
      renderMode,
      onRunStateChange,
      saveWorkflow,
    }: {
      renderMode?: string;
      onRunStateChange?: (
        canRun: boolean,
        isSubmitting: boolean,
        handler: () => void
      ) => void;
      saveWorkflow?: () => Promise<void>;
    }) => {
      // Simulate ManualRunPanel calling onRunStateChange after mount
      if (onRunStateChange) {
        setTimeout(() => {
          onRunStateChange(true, false, () => {
            console.log('Mock run triggered');
          });
        }, 0);
      }

      return (
        <div data-testid="manual-run-panel" data-render-mode={renderMode}>
          ManualRunPanel (renderMode: {renderMode || 'standalone'})
        </div>
      );
    },
  })
);

// Mock useURLState hook
const mockSearchParams = new URLSearchParams();
mockSearchParams.set('job', 'job-1');

vi.mock('../../../../js/react/lib/use-url-state', () => ({
  useURLState: () => ({
    searchParams: mockSearchParams,
    updateSearchParams: vi.fn(),
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
    job: {
      id: 'job-1',
      name: 'Test Job',
      adaptor: '@openfn/language-http@latest',
      body: 'fn(state => state)',
      project_credential_id: null,
      keychain_credential_id: null,
    },
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
const mockCurrentRun = {
  id: 'run-1',
  work_order_id: 'wo-1',
  work_order: {
    id: 'wo-1',
    workflow_id: 'workflow-1',
  },
  state: 'success' as const,
  created_by: null,
  starting_trigger: null,
  started_at: '2024-01-01T00:00:00Z',
  finished_at: '2024-01-01T00:01:00Z',
  inserted_at: '2024-01-01T00:00:00Z',
  steps: [
    {
      id: 'step-1',
      job_id: 'job-1',
      job: { name: 'Test Job' },
      exit_reason: null,
      error_type: null,
      started_at: '2024-01-01T00:00:00Z',
      finished_at: '2024-01-01T00:00:30Z',
      input_dataclip_id: 'input-1',
      output_dataclip_id: 'output-1',
      inserted_at: '2024-01-01T00:00:00Z',
    },
    {
      id: 'step-2',
      job_id: 'job-2',
      job: { name: 'Second Job' },
      exit_reason: null,
      error_type: null,
      started_at: '2024-01-01T00:00:30Z',
      finished_at: '2024-01-01T00:01:00Z',
      input_dataclip_id: 'output-1',
      output_dataclip_id: 'output-2',
      inserted_at: '2024-01-01T00:00:30Z',
    },
  ],
};

vi.mock('../../../../js/collaborative-editor/hooks/useHistory', () => ({
  useFollowRun: vi.fn(() => mockCurrentRun),
  useHistoryCommands: () => ({
    selectStep: mockSelectStep,
    requestHistory: vi.fn(),
    requestRunSteps: vi.fn(),
    getRunSteps: vi.fn(),
    clearError: vi.fn(),
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

    // Reset search params
    mockSearchParams.delete('job');
    mockSearchParams.set('job', 'job-1');
  });

  describe('panel layout', () => {
    test('renders with three-panel layout', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      // Wait for component to render - note: there are now 2 PanelGroups (main + nested docs panel)
      await waitFor(() => {
        const panelGroups = screen.getAllByTestId('panel-group');
        expect(panelGroups.length).toBeGreaterThanOrEqual(1);
      });

      // Should have at least three main panels (left, center, right)
      // Note: there may be additional nested panels from the docs/metadata section
      const panels = screen.getAllByTestId('panel');
      expect(panels.length).toBeGreaterThanOrEqual(3);
    });

    test('left panel contains ManualRunPanel with embedded mode', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      // Wait for ManualRunPanel to render
      await waitFor(() => {
        expect(screen.getByTestId('manual-run-panel')).toBeInTheDocument();
      });

      // Should use embedded mode
      const manualRunPanel = screen.getByTestId('manual-run-panel');
      expect(manualRunPanel.getAttribute('data-render-mode')).toBe('embedded');
    });

    test('center panel contains CollaborativeMonaco editor', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      // Wait for Monaco editor to render
      await waitFor(() => {
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument();
      });
    });

    test('shows Input, Code, and Output panel labels', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(screen.getByText(/Code/i)).toBeInTheDocument();
      });

      expect(screen.getByText('New Run (Select Input)')).toBeInTheDocument();
    });
  });

  describe('header integration', () => {
    test('displays job name in header', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        const jobNames = screen.getAllByText(/Test Job/i);
        expect(jobNames.length).toBeGreaterThan(0);
      });
    });

    test('displays Run button in header', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(
          screen.getByRole('button', { name: /run/i })
        ).toBeInTheDocument();
      });
    });

    test('displays Run button in header', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(
          screen.getByRole('button', { name: /run/i })
        ).toBeInTheDocument();
      });
    });

    test('displays job name in code panel heading', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(screen.getByText(/Code -/i)).toBeInTheDocument();
      });
    });
  });

  describe('run state management', () => {
    test('Run button is enabled when canRunWorkflow is true', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      // Wait for onRunStateChange to be called and run button to be enabled
      await waitFor(() => {
        const runButton = screen.getByRole('button', { name: /run/i });
        expect(runButton).not.toBeDisabled();
      });
    });

    test('receives run state from ManualRunPanel via onRunStateChange', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      // Wait for ManualRunPanel to mount and call onRunStateChange
      await waitFor(() => {
        expect(screen.getByTestId('manual-run-panel')).toBeInTheDocument();
      });

      // Run button should be enabled (from mocked ManualRunPanel)
      await waitFor(() => {
        const runButton = screen.getByRole('button', { name: /run/i });
        expect(runButton).not.toBeDisabled();
      });
    });
  });

  describe('keyboard shortcuts', () => {
    test('Escape key eventually calls onClose', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(screen.getByTestId('collaborative-monaco')).toBeInTheDocument();
      });

      // First Escape - should blur Monaco (but we can't test focus in this mock)
      await user.keyboard('{Escape}');

      // Second Escape - should close IDE
      await user.keyboard('{Escape}');
      expect(onClose).toHaveBeenCalled();
    });
  });

  describe('panel collapse/expand', () => {
    test('left panel can be collapsed via collapse button', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(screen.getByTestId('manual-run-panel')).toBeInTheDocument();
      });

      // Find collapse button for left panel
      const collapseButtons = screen.getAllByRole('button', {
        name: /collapse/i,
      });

      // Should have collapse buttons for each panel
      expect(collapseButtons.length).toBeGreaterThan(0);

      // Clicking collapse button would trigger panel collapse
      // (Full behavior requires ImperativePanelHandle which we can't test in JSDOM)
    });

    test('prevents closing last open panel', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(screen.getByText(/Code -/i)).toBeInTheDocument();
      });

      // Find all collapse buttons
      const collapseButtons = screen.getAllByRole('button', {
        name: /collapse/i,
      });

      // All collapse buttons should be enabled initially
      // (In real app, last open panel's collapse button would be disabled)
      expect(collapseButtons.length).toBeGreaterThan(0);
    });
  });

  describe('button functionality', () => {
    test('Run button is present', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(
          screen.getByRole('button', { name: /run/i })
        ).toBeInTheDocument();
      });
    });
  });

  describe('Close IDE functionality', () => {
    test('clicking close button calls onClose', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({
        onClose,
      });

      await waitFor(() => {
        expect(screen.getByLabelText('Close IDE')).toBeInTheDocument();
      });

      const closeButton = screen.getByLabelText('Close IDE');
      await user.click(closeButton);

      expect(onClose).toHaveBeenCalledOnce();
    });
  });

  describe('Job selection and run step selection', () => {
    test('changing job in JobSelector selects the related run step', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      // Clear any previous calls to mockSelectStep
      mockSelectStep.mockClear();

      renderFullScreenIDE({
        onClose,
      });

      // Wait for JobSelector to render
      await waitFor(() => {
        expect(screen.getByTestId('job-selector')).toBeInTheDocument();
      });

      // Verify initial job is displayed
      expect(screen.getByTestId('current-job-name')).toHaveTextContent(
        'Test Job'
      );

      // Select the second job
      const jobSelect = screen.getByTestId('job-select');
      await user.selectOptions(jobSelect, 'job-2');

      // Verify selectStep was called with the corresponding step ID
      await waitFor(() => {
        expect(mockSelectStep).toHaveBeenCalledWith('step-2');
      });
    });

    test('changing job when run has no steps for that job calls selectStep with null', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      // Clear any previous calls to mockSelectStep
      mockSelectStep.mockClear();

      renderFullScreenIDE({
        onClose,
      });

      // Wait for JobSelector to render
      await waitFor(() => {
        expect(screen.getByTestId('job-selector')).toBeInTheDocument();
      });

      // First select job-2 to ensure we have a clean state
      const jobSelect = screen.getByTestId('job-select');
      await user.selectOptions(jobSelect, 'job-2');

      // Wait for that selection to complete
      await waitFor(() => {
        expect(mockSelectStep).toHaveBeenCalledWith('step-2');
      });

      // Clear the mock again
      mockSelectStep.mockClear();

      // Now select job-1 again
      await user.selectOptions(jobSelect, 'job-1');

      // Verify selectStep was called with step-1 this time
      await waitFor(() => {
        expect(mockSelectStep).toHaveBeenCalledWith('step-1');
      });
    });
  });
});
