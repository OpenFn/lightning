/**
 * FullScreenIDE Component Tests
 *
 * Tests the FullScreenIDE component state machine for the right panel:
 * - No panel state (initial): Panel hidden, History and Run buttons in header
 * - Create-run state: ManualRunPanel with input selection
 * - History state: MiniHistory with run list
 * - Run-viewer state: RunViewerPanel with loaded run
 *
 * Also tests:
 * - Header buttons for History and Run
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
    ManualRunPanel: ({
      renderMode,
      onClosePanel,
    }: {
      renderMode?: string;
      onClosePanel?: () => void;
    }) => (
      <div data-testid="manual-run-panel" data-render-mode={renderMode}>
        ManualRunPanel (renderMode: {renderMode || 'standalone'})
        {onClosePanel && (
          <button data-testid="close-panel-btn" onClick={onClosePanel}>
            Close Panel
          </button>
        )}
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
let mockParams: Record<string, string> = { job: 'job-1' };
const mockUpdateSearchParams = vi.fn(
  (params: Record<string, string | null>) => {
    Object.entries(params).forEach(([key, value]) => {
      if (value === null) {
        delete mockParams[key];
      } else {
        mockParams[key] = value;
      }
    });
  }
);

vi.mock('../../../../js/react/lib/use-url-state', () => ({
  useURLState: () => ({
    params: mockParams,
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
    setCurrentNode: vi.fn(),
    setURLfromSelection: vi.fn(),
    selectNode: vi.fn(),
    selectTrigger: vi.fn(),
    selectEdge: vi.fn(),
  }),
  useWorkflowState: (selector: (state: any) => any) =>
    selector({ workflow: mockWorkflow }),
  useSaveWorkflow: () => ({
    saveWorkflow: vi.fn().mockResolvedValue(null),
    isSaving: false,
    error: null,
  }),
  useWorkflowActions: () => ({
    updateWorkflow: vi.fn(),
    selectJob: vi.fn(),
    updateJob: vi.fn(),
  }),
}));

// Mock history hooks
const mockRequestHistory = vi.fn();
const mockClearError = vi.fn();

vi.mock('../../../../js/collaborative-editor/hooks/useHistory', () => ({
  useHistory: () => [],
  useHistoryLoading: () => false,
  useHistoryError: () => null,
  useHistoryChannelConnected: () => true,
  useHistoryCommands: () => ({
    requestHistory: mockRequestHistory,
    clearError: mockClearError,
    selectStep: vi.fn(),
  }),
  useFollowRun: () => ({
    run: null,
    clearRun: vi.fn(),
  }),
  useActiveRun: () => null,
  useActiveRunLoading: () => false,
  useActiveRunError: () => null,
  useSelectedStepId: () => null,
  useSelectedStep: () => null,
  useJobMatchesRun: () => true,
  useRunSteps: () => null,
}));

// Mock adaptor hooks
vi.mock('../../../../js/collaborative-editor/hooks/useAdaptors', () => ({
  useFetchAdaptorDocs: () => ({
    data: null,
    loading: false,
    error: null,
  }),
  useFetchAdaptorList: () => ({
    data: [],
    loading: false,
    error: null,
  }),
  useProjectAdaptors: () => ({
    projectAdaptors: [],
    allAdaptors: [],
  }),
  useAdaptors: () => [],
}));

// Mock credentials hooks
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
  }),
}));

// Mock LiveView actions context
vi.mock(
  '../../../../js/collaborative-editor/contexts/LiveViewActionsContext',
  () => ({
    useLiveViewActions: () => ({
      pushEvent: vi.fn(),
      handleEvent: vi.fn(),
    }),
  })
);

// Mock Run hooks
vi.mock('../../../../js/collaborative-editor/hooks/useRunRetry', () => ({
  useRunRetry: () => ({
    handleRun: vi.fn(),
    handleRetry: vi.fn(),
    isRetryable: false,
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
    Object.keys(mockParams).forEach(key => delete mockParams[key]);
    mockParams.job = 'job-1';
  });

  describe('Initial State', () => {
    test('displays History and Run buttons in header', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('History')).toBeInTheDocument();
        expect(screen.getByText('Run')).toBeInTheDocument();
      });
    });

    test('right panel is not shown initially', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('History')).toBeInTheDocument();
      });

      // ManualRunPanel and MiniHistory should not be visible initially
      expect(screen.queryByTestId('manual-run-panel')).not.toBeInTheDocument();
      expect(screen.queryByTestId('mini-history')).not.toBeInTheDocument();
    });
  });

  describe('Run Button Flow', () => {
    test('clicking Run shows ManualRunPanel', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('Run')).toBeInTheDocument();
      });

      // Click Run
      await user.click(screen.getByText('Run'));

      // Should now show ManualRunPanel
      await waitFor(() => {
        expect(screen.getByTestId('manual-run-panel')).toBeInTheDocument();
      });
    });

    test('closing ManualRunPanel hides the panel', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('Run')).toBeInTheDocument();
      });

      // Click Run to open panel
      await user.click(screen.getByText('Run'));

      await waitFor(() => {
        expect(screen.getByTestId('manual-run-panel')).toBeInTheDocument();
      });

      // Click close panel button
      const closeButton = screen.getByTestId('close-panel-btn');
      await user.click(closeButton);

      // Panel should be hidden
      await waitFor(() => {
        expect(
          screen.queryByTestId('manual-run-panel')
        ).not.toBeInTheDocument();
      });
    });
  });

  describe('History Button Flow', () => {
    test('clicking History shows MiniHistory', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('History')).toBeInTheDocument();
      });

      // Click History
      await user.click(screen.getByText('History'));

      // Should now show MiniHistory
      await waitFor(() => {
        expect(screen.getByTestId('mini-history')).toBeInTheDocument();
      });

      // Should have requested history
      expect(mockRequestHistory).toHaveBeenCalled();
    });

    test('closing MiniHistory hides the panel', async () => {
      const user = userEvent.setup();
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(screen.getByText('History')).toBeInTheDocument();
      });

      // Click History to open panel
      await user.click(screen.getByText('History'));

      await waitFor(() => {
        expect(screen.getByTestId('mini-history')).toBeInTheDocument();
      });

      // Click back button in MiniHistory
      const backButton = screen.getByTestId('mini-history-back');
      await user.click(backButton);

      // Panel should be hidden
      await waitFor(() => {
        expect(screen.queryByTestId('mini-history')).not.toBeInTheDocument();
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

    test('displays Docs and Metadata buttons in header', async () => {
      const onClose = vi.fn();

      renderFullScreenIDE({ onClose });

      await waitFor(() => {
        expect(
          screen.getByTitle('Show adaptor documentation')
        ).toBeInTheDocument();
        expect(screen.getByTitle('Show metadata explorer')).toBeInTheDocument();
      });
    });
  });
});
