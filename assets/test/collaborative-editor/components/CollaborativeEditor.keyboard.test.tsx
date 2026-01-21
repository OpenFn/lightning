/**
 * CollaborativeEditor IDE Keyboard Shortcuts Tests
 *
 * Tests keyboard shortcut behavior for the IDE functionality in CollaborativeEditor.
 * The Cmd+E/Ctrl+E shortcut is registered in the IDEWrapper component within
 * CollaborativeEditor, not in WorkflowEditor.
 *
 * Shortcuts tested:
 * - Cmd+E / Ctrl+E: Open job editor (IDE) for selected job
 *
 * Architecture Note:
 * These tests render the full CollaborativeEditor component because the Cmd+E
 * keyboard shortcut is registered in the IDEWrapper component (lines 991-1004
 * in CollaborativeEditor.tsx), which is a child of CollaborativeEditor.
 */

import { screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import { CollaborativeEditor } from '../../../js/collaborative-editor/CollaborativeEditor';
import type { Workflow } from '../../../js/collaborative-editor/types/workflow';
import {
  expectShortcutNotToFire,
  keys,
  renderWithKeyboard,
} from '../../keyboard-test-utils';
import {
  createMockURLState,
  getURLStateMockValue,
} from '../__helpers__/urlStateMocks';

// Mock Socket
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

// Mock dependencies
vi.mock('../../../js/collaborative-editor/api/dataclips', () => ({
  searchDataclips: vi.fn(() =>
    Promise.resolve({
      data: [],
      next_cron_run_dataclip_id: null,
      can_edit_dataclip: true,
    })
  ),
}));

// Mock MonacoEditor
vi.mock('@monaco-editor/react', () => ({
  default: ({ value }: { value: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
}));

// Mock CollaborativeWorkflowDiagram
vi.mock(
  '../../../js/collaborative-editor/components/diagram/CollaborativeWorkflowDiagram',
  () => ({
    CollaborativeWorkflowDiagram: () => (
      <div data-testid="workflow-diagram">Workflow Diagram</div>
    ),
  })
);

// Mock Inspector
vi.mock('../../../js/collaborative-editor/components/inspector', () => ({
  Inspector: () => <div data-testid="inspector">Inspector</div>,
}));

// Mock LeftPanel
vi.mock('../../../js/collaborative-editor/components/left-panel', () => ({
  LeftPanel: () => <div data-testid="left-panel">Left Panel</div>,
}));

// Mock FullScreenIDE
// Note: The real FullScreenIDE has Escape key handler that calls onClose
// We need to import useKeyboardShortcut here to simulate that behavior
vi.mock(
  '../../../js/collaborative-editor/components/ide/FullScreenIDE',
  async () => {
    const { useKeyboardShortcut } = await import(
      '../../../js/collaborative-editor/keyboard'
    );

    return {
      FullScreenIDE: ({ onClose }: { onClose: () => void }) => {
        // Simulate Escape key handler from real FullScreenIDE (line 563)
        useKeyboardShortcut(
          'Escape',
          () => {
            onClose();
          },
          50
        );

        return (
          <div data-testid="fullscreen-ide">
            Full Screen IDE
            <button data-testid="close-ide" onClick={onClose}>
              Close
            </button>
          </div>
        );
      },
    };
  }
);

// Mock ManualRunPanel
vi.mock('../../../js/collaborative-editor/components/ManualRunPanel', () => ({
  ManualRunPanel: ({
    jobId,
    triggerId,
  }: {
    jobId?: string;
    triggerId?: string;
  }) => (
    <div
      data-testid="manual-run-panel"
      data-job-id={jobId}
      data-trigger-id={triggerId}
    >
      ManualRunPanel
    </div>
  ),
}));

// Mock AIAssistantPanelWrapper (this is what CollaborativeEditor imports)
vi.mock(
  '../../../js/collaborative-editor/components/AIAssistantPanelWrapper',
  () => ({
    AIAssistantPanelWrapper: () => (
      <div data-testid="ai-assistant-panel-wrapper">
        AI Assistant Panel Wrapper
      </div>
    ),
  })
);

// Mock Toaster
vi.mock('../../../js/collaborative-editor/components/ui/Toaster', () => ({
  Toaster: () => <div data-testid="toaster">Toaster</div>,
}));

// Mock VersionDropdown and related components
vi.mock('../../../js/collaborative-editor/components/VersionDropdown', () => ({
  VersionDropdown: () => <div data-testid="version-dropdown">Versions</div>,
}));

vi.mock(
  '../../../js/collaborative-editor/components/VersionDebugLogger',
  () => ({
    VersionDebugLogger: () => null,
  })
);

vi.mock('../../../js/collaborative-editor/components/LoadingBoundary', () => ({
  LoadingBoundary: ({ children }: { children: React.ReactNode }) => (
    <>{children}</>
  ),
}));

// Mock CredentialModalContext
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

// Create controllable mocks
const mockSelectNode = vi.fn();
const urlState = createMockURLState();

// Mock useURLState
vi.mock('../../../js/react/lib/use-url-state', () => ({
  useURLState: () => getURLStateMockValue(urlState),
}));

// Mock session context hooks
vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useIsNewWorkflow: () => false,
  useProjectRepoConnection: () => undefined,
  useProject: () => ({
    id: 'project-1',
    name: 'Test Project',
  }),
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
  useAppConfig: () => ({
    email_verification_enabled: false,
  }),
  useLimits: () => ({
    runs: { allowed: true, message: null },
    workflow_activation: { allowed: true, message: null },
    github_sync: { allowed: true, message: null },
  }),
  useSessionContext: () => ({
    workflow: {
      jobs: [
        {
          id: '5887a56d-19b0-452f-8891-9c7a72116325',
          body: '// Validate and transform the data you\'ve received...\nfn(state => {\n  console.log("Do some data transformation here");\n  return state;\n})\n',
          name: 'Transform data',
          adaptor: '@openfn/language-common@3.2.1',
        },
      ],
      triggers: [
        {
          id: '000311a3-f84c-4990-8a74-824ccf0e0561',
          comment: null,
          custom_path: null,
          cron_expression: null,
          type: 'webhook',
          enabled: true,
          webhook_reply: 'before_start',
        },
      ],
      edges: [
        {
          id: '772ef8d2-f5e9-4437-81e8-ca0c68c8315b',
          condition_type: 'always',
          condition_expression: null,
          condition_label: null,
          enabled: true,
          source_job_id: null,
          source_trigger_id: '000311a3-f84c-4990-8a74-824ccf0e0561',
          target_job_id: '5887a56d-19b0-452f-8891-9c7a72116325',
        },
      ],
      name: 'simple-worfklow',
      positions: {},
    },
  }),
}));

// Mock workflow hooks with controllable node selection
let currentNode: {
  type: 'job' | 'trigger' | 'edge' | null;
  node: any;
} = {
  type: null,
  node: null,
};

// Create mock workflow
const mockWorkflow: Workflow = {
  id: 'workflow-1',
  name: 'Test Workflow',
  jobs: [
    {
      id: 'job-1',
      name: 'Job 1',
      adaptor: '@openfn/language-http@latest',
      body: 'fn(state => state)',
      enabled: true,
      project_credential_id: null,
      keychain_credential_id: null,
    },
    {
      id: 'job-2',
      name: 'Job 2',
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

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useNodeSelection: () => ({
    currentNode,
    selectNode: mockSelectNode,
  }),
  useWorkflowStoreContext: () => ({
    validateWorkflowName: vi.fn(),
    importWorkflow: vi.fn(),
  }),
  useWorkflowActions: () => ({
    saveWorkflow: vi.fn(),
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
  useCanRun: () => ({
    canRun: true,
    tooltipMessage: '',
  }),
  useWorkflowEnabled: () => ({
    enabled: true,
    setEnabled: vi.fn(),
  }),
  useCanSave: () => ({
    canSave: true,
    tooltipMessage: '',
  }),
  useWorkflowSettingsErrors: () => ({
    hasErrors: false,
    errors: [],
  }),
  useWorkflowReadOnly: () => ({
    isReadOnly: false,
    tooltipMessage: '',
  }),
}));

// Mock UI hooks
const mockIsRunPanelOpen = vi.fn(() => false);
const mockRunPanelContext = vi.fn(() => null);
const mockIsAIAssistantPanelOpen = vi.fn(() => false);

vi.mock('../../../js/collaborative-editor/hooks/useUI', () => ({
  useIsRunPanelOpen: () => mockIsRunPanelOpen(),
  useRunPanelContext: () => mockRunPanelContext(),
  useIsAIAssistantPanelOpen: () => mockIsAIAssistantPanelOpen(),
  useAIAssistantInitialMessage: () => null,
  useIsGitHubSyncModalOpen: () => false,
  useIsCreateWorkflowPanelCollapsed: () => true,
  useImportPanelState: () => 'initial',
  useUICommands: () => ({
    openRunPanel: vi.fn(),
    closeRunPanel: vi.fn(),
    openAIAssistantPanel: vi.fn(),
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
    error: null,
    searchQuery: '',
    selectedTemplate: null,
  }),
}));

// Mock AI Assistant hooks
vi.mock('../../../js/collaborative-editor/hooks/useAIAssistant', () => ({
  useAIStore: () => ({
    disconnect: vi.fn(),
    getState: vi.fn(() => ({})),
  }),
  useAIMessages: () => [],
  useAIIsLoading: () => false,
  useAISessionId: () => null,
  useAISessionType: () => null,
  useAIConnectionState: () => 'disconnected',
  useAIHasReadDisclaimer: () => true,
  useAIWorkflowTemplateContext: () => null,
}));

vi.mock('../../../js/collaborative-editor/hooks/useAIMode', () => ({
  useAIMode: () => ({
    mode: 'workflow' as const,
    jobId: null,
  }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useAIAssistantChannel', () => ({
  useAIAssistantChannel: () => ({
    sendMessage: vi.fn(),
    loadSessions: vi.fn(),
    updateContext: vi.fn(),
    retryMessage: vi.fn(),
    markDisclaimerRead: vi.fn(),
  }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useVersionSelect', () => ({
  useVersionSelect: () => vi.fn(),
}));

describe('CollaborativeEditor IDE keyboard shortcuts', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    urlState.reset();

    // Reset state
    mockIsRunPanelOpen.mockReturnValue(false);
    mockRunPanelContext.mockReturnValue(null);
    mockIsAIAssistantPanelOpen.mockReturnValue(false);
    currentNode = { type: null, node: null };
  });

  describe('Cmd+E - Open Job Editor (IDE)', () => {
    test('opens IDE for selected job with Cmd+E on Mac', async () => {
      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      // Update URL params to select the job
      urlState.setParams({ job: 'job-1' });

      const { container, shortcuts } = renderWithKeyboard(
        <CollaborativeEditor
          data-workflow-id="workflow-1"
          data-workflow-name="Test Workflow"
          data-project-id="project-1"
          data-project-name="Test Project"
        />
      );

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      await shortcuts.openIDE('cmd');

      await waitFor(() => {
        expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
          panel: 'editor',
        });
      });
    });

    test('opens IDE for selected job with Ctrl+E on Windows/Linux', async () => {
      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      urlState.setParams({ job: 'job-1' });

      const { container, shortcuts } = renderWithKeyboard(
        <CollaborativeEditor
          data-workflow-id="workflow-1"
          data-workflow-name="Test Workflow"
          data-project-id="project-1"
          data-project-name="Test Project"
        />
      );

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      await shortcuts.openIDE('ctrl');

      await waitFor(() => {
        expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
          panel: 'editor',
        });
      });
    });

    test('does not open IDE when trigger is selected', async () => {
      currentNode = {
        type: 'trigger',
        node: mockWorkflow.triggers[0],
      };

      const { container, user } = renderWithKeyboard(
        <CollaborativeEditor
          data-workflow-id="workflow-1"
          data-workflow-name="Test Workflow"
          data-project-id="project-1"
          data-project-name="Test Project"
        />
      );

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      await expectShortcutNotToFire(
        keys.ctrl('e'),
        urlState.mockFns.updateSearchParams,
        user
      );
    });

    test('does not open IDE when nothing is selected', async () => {
      currentNode = { type: null, node: null };

      const { container, user } = renderWithKeyboard(
        <CollaborativeEditor
          data-workflow-id="workflow-1"
          data-workflow-name="Test Workflow"
          data-project-id="project-1"
          data-project-name="Test Project"
        />
      );

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      await expectShortcutNotToFire(
        keys.ctrl('e'),
        urlState.mockFns.updateSearchParams,
        user
      );
    });

    test('does not trigger when IDE is already open', async () => {
      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      // IDE is already open
      urlState.setParams({ panel: 'editor', job: 'job-1' });

      const { container, user } = renderWithKeyboard(
        <CollaborativeEditor
          data-workflow-id="workflow-1"
          data-workflow-name="Test Workflow"
          data-project-id="project-1"
          data-project-name="Test Project"
        />
      );

      await waitFor(() => {
        expect(screen.getByTestId('fullscreen-ide')).toBeInTheDocument();
      });

      container.focus();

      await expectShortcutNotToFire(
        keys.ctrl('e'),
        urlState.mockFns.updateSearchParams,
        user
      );
    });

    test('works in form fields (enableOnFormTags)', async () => {
      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      urlState.setParams({ job: 'job-1' });

      const { container, shortcuts } = renderWithKeyboard(
        <CollaborativeEditor
          data-workflow-id="workflow-1"
          data-workflow-name="Test Workflow"
          data-project-id="project-1"
          data-project-name="Test Project"
        />
      );

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      // Create and focus an input field
      const input = document.createElement('input');
      container.appendChild(input);
      input.focus();

      await shortcuts.openIDE('cmd');

      await waitFor(() => {
        expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
          panel: 'editor',
        });
      });
    });
  });

  describe('guard conditions', () => {
    test('Cmd+E only works for job nodes', async () => {
      // Test with edge selection (should not work)
      currentNode = {
        type: 'edge',
        node: { id: 'edge-1' },
      };

      const { container, user } = renderWithKeyboard(
        <CollaborativeEditor
          data-workflow-id="workflow-1"
          data-workflow-name="Test Workflow"
          data-project-id="project-1"
          data-project-name="Test Project"
        />
      );

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      await expectShortcutNotToFire(
        keys.ctrl('e'),
        urlState.mockFns.updateSearchParams,
        user
      );
    });

    test('Cmd+E disabled when IDE already open', async () => {
      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      urlState.setParams({ panel: 'editor', job: 'job-1' });

      const { container, user } = renderWithKeyboard(
        <CollaborativeEditor
          data-workflow-id="workflow-1"
          data-workflow-name="Test Workflow"
          data-project-id="project-1"
          data-project-name="Test Project"
        />
      );

      await waitFor(() => {
        expect(screen.getByTestId('fullscreen-ide')).toBeInTheDocument();
      });

      container.focus();

      await expectShortcutNotToFire(
        keys.cmd('e'),
        urlState.mockFns.updateSearchParams,
        user
      );
    });
  });

  describe('IDE open/close cycle', () => {
    test('preserves job selection when closing IDE with Escape', async () => {
      // REGRESSION TEST for IDE close behavior
      // This test verifies that closing the IDE preserves job selection
      //
      // Expected behavior:
      // - Closing IDE should only clear 'panel' param
      // - Job selection ('job' param) should be preserved
      // - User can reopen IDE to same job with Cmd+E

      // 1. Start with a selected job
      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      // Simulate URL state with job selected but IDE closed
      urlState.setParams({ job: 'job-1' });

      const { container, shortcuts, rerender } = renderWithKeyboard(
        <CollaborativeEditor
          data-workflow-id="workflow-1"
          data-workflow-name="Test Workflow"
          data-project-id="project-1"
          data-project-name="Test Project"
        />
      );

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      // 2. Open IDE with Cmd+E - should set panel=editor
      await shortcuts.openIDE('cmd');

      await waitFor(() => {
        expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
          panel: 'editor',
        });
      });

      // Simulate URL state change to open IDE
      urlState.setParam('panel', 'editor');

      // Force re-render with updated params
      rerender(
        <CollaborativeEditor
          data-workflow-id="workflow-1"
          data-workflow-name="Test Workflow"
          data-project-id="project-1"
          data-project-name="Test Project"
        />
      );

      // Wait for IDE to render
      await waitFor(() => {
        expect(screen.getByTestId('fullscreen-ide')).toBeInTheDocument();
      });

      vi.clearAllMocks();

      // 3. Close IDE with Escape
      await shortcuts.escape();

      await waitFor(() => {
        expect(urlState.mockFns.updateSearchParams).toHaveBeenCalled();
      });

      // CORRECT BEHAVIOR: Closing IDE should only clear the panel parameter,
      // preserving the job selection so user can reopen IDE with Cmd+E
      expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
        panel: null,
      });

      // Verify we're NOT clearing the job parameter
      expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalledWith({
        panel: null,
        job: null,
      });
    });
  });
});
