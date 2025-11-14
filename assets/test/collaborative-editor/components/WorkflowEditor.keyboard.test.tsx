/**
 * WorkflowEditor Keyboard Shortcuts Tests
 *
 * Tests keyboard shortcut behavior in WorkflowEditor using a library-agnostic
 * approach that tests user-facing behavior rather than implementation details.
 * Tests survive library migrations and document expected user behavior.
 *
 * Shortcuts tested:
 * - Cmd+E: Open job editor (IDE) for selected job
 * - Mod+Enter: Open run panel for selected node or first trigger
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import { HotkeysProvider } from 'react-hotkeys-hook';
import { WorkflowEditor } from '../../../js/collaborative-editor/components/WorkflowEditor';
import type { Workflow } from '../../../js/collaborative-editor/types/workflow';

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
vi.mock(
  '../../../js/collaborative-editor/components/ide/FullScreenIDE',
  () => ({
    FullScreenIDE: () => (
      <div data-testid="fullscreen-ide">Full Screen IDE</div>
    ),
  })
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

// Create controllable mocks
const mockUpdateSearchParams = vi.fn();
const mockOpenRunPanel = vi.fn();
const mockCloseRunPanel = vi.fn();
const mockSelectNode = vi.fn();
const mockSearchParams = new URLSearchParams();

// Mock useURLState
vi.mock('../../../js/react/lib/use-url-state', () => ({
  useURLState: () => ({
    searchParams: mockSearchParams,
    updateSearchParams: mockUpdateSearchParams,
    hash: '',
  }),
}));

// Mock session context hooks
vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useIsNewWorkflow: () => false,
  useProjectRepoConnection: () => undefined,
  useProject: () => ({
    id: 'project-1',
    name: 'Test Project',
  }),
}));

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
    {
      id: 'trigger-2',
      type: 'cron',
      enabled: true,
    },
  ],
  edges: [],
};

// Mock UI hooks with controllable state
const mockIsRunPanelOpen = vi.fn(() => false);
const mockRunPanelContext = vi.fn(() => null);

vi.mock('../../../js/collaborative-editor/hooks/useUI', () => ({
  useIsRunPanelOpen: () => mockIsRunPanelOpen(),
  useRunPanelContext: () => mockRunPanelContext(),
  useUICommands: () => ({
    openRunPanel: mockOpenRunPanel,
    closeRunPanel: mockCloseRunPanel,
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
}));

// Helper function to render WorkflowEditor with HotkeysProvider
function renderWorkflowEditor() {
  return render(
    <HotkeysProvider>
      <WorkflowEditor />
    </HotkeysProvider>
  );
}

describe('WorkflowEditor keyboard shortcuts', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    // Reset state
    mockSearchParams.delete('panel');
    mockSearchParams.delete('job');
    mockIsRunPanelOpen.mockReturnValue(false);
    mockRunPanelContext.mockReturnValue(null);
    currentNode = { type: null, node: null };
  });

  describe('Cmd+E - Open Job Editor (IDE)', () => {
    test('opens IDE for selected job with Cmd+E on Mac', async () => {
      const user = userEvent.setup();

      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      // Press Cmd+E (Mac)
      await user.keyboard('{Meta>}e{/Meta}');

      await waitFor(() => {
        expect(mockUpdateSearchParams).toHaveBeenCalledWith({
          panel: 'editor',
        });
      });
    });

    test('opens IDE for selected job with Ctrl+E on Windows/Linux', async () => {
      const user = userEvent.setup();

      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      // Press Ctrl+E (Windows/Linux)
      await user.keyboard('{Control>}e{/Control}');

      await waitFor(() => {
        expect(mockUpdateSearchParams).toHaveBeenCalledWith({
          panel: 'editor',
        });
      });
    });

    test('does not open IDE when trigger is selected', async () => {
      const user = userEvent.setup();

      currentNode = {
        type: 'trigger',
        node: mockWorkflow.triggers[0],
      };

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      await user.keyboard('{Control>}e{/Control}');

      // Wait to ensure handler doesn't fire
      await new Promise(resolve => setTimeout(resolve, 100));
      expect(mockUpdateSearchParams).not.toHaveBeenCalled();
    });

    test('does not open IDE when nothing is selected', async () => {
      const user = userEvent.setup();

      currentNode = { type: null, node: null };

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      await user.keyboard('{Control>}e{/Control}');

      await new Promise(resolve => setTimeout(resolve, 100));
      expect(mockUpdateSearchParams).not.toHaveBeenCalled();
    });

    test('does not trigger when IDE is already open', async () => {
      const user = userEvent.setup();

      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      // IDE is already open
      mockSearchParams.set('panel', 'editor');
      mockSearchParams.set('job', 'job-1');

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('fullscreen-ide')).toBeInTheDocument();
      });

      container.focus();

      await user.keyboard('{Control>}e{/Control}');

      // Wait to ensure handler doesn't fire
      await new Promise(resolve => setTimeout(resolve, 100));
      expect(mockUpdateSearchParams).not.toHaveBeenCalled();
    });

    test('works in form fields (enableOnFormTags)', async () => {
      const user = userEvent.setup();

      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      // Create and focus an input field
      const input = document.createElement('input');
      container.appendChild(input);
      input.focus();

      // Press Cmd+E while input is focused
      await user.keyboard('{Meta>}e{/Meta}');

      await waitFor(() => {
        expect(mockUpdateSearchParams).toHaveBeenCalledWith({
          panel: 'editor',
        });
      });
    });
  });

  describe('Mod+Enter - Open Run Panel', () => {
    test('opens run panel for selected job with Cmd+Enter on Mac', async () => {
      const user = userEvent.setup();

      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      // Press Cmd+Enter (Mac)
      await user.keyboard('{Meta>}{Enter}{/Meta}');

      await waitFor(() => {
        expect(mockOpenRunPanel).toHaveBeenCalledWith({ jobId: 'job-1' });
      });
    });

    test('opens run panel for selected job with Ctrl+Enter on Windows/Linux', async () => {
      const user = userEvent.setup();

      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      // Press Ctrl+Enter (Windows/Linux)
      await user.keyboard('{Control>}{Enter}{/Control}');

      await waitFor(() => {
        expect(mockOpenRunPanel).toHaveBeenCalledWith({ jobId: 'job-1' });
      });
    });

    test('opens run panel for selected trigger', async () => {
      const user = userEvent.setup();

      currentNode = {
        type: 'trigger',
        node: mockWorkflow.triggers[0],
      };

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      await user.keyboard('{Meta>}{Enter}{/Meta}');

      await waitFor(() => {
        expect(mockOpenRunPanel).toHaveBeenCalledWith({
          triggerId: 'trigger-1',
        });
      });
    });

    test('falls back to first trigger when nothing selected', async () => {
      const user = userEvent.setup();

      currentNode = { type: null, node: null };

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      await user.keyboard('{Meta>}{Enter}{/Meta}');

      await waitFor(() => {
        expect(mockOpenRunPanel).toHaveBeenCalledWith({
          triggerId: 'trigger-1',
        });
      });
    });

    test('delegates to ManualRunPanel when run panel already open', async () => {
      const user = userEvent.setup();

      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      // Run panel is already open
      mockIsRunPanelOpen.mockReturnValue(true);
      mockRunPanelContext.mockReturnValue({ jobId: 'job-1' });

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('manual-run-panel')).toBeInTheDocument();
      });

      container.focus();

      // Try to open run panel again - should not call openRunPanel
      // (ManualRunPanel's shortcut handler will execute instead)
      await user.keyboard('{Meta>}{Enter}{/Meta}');

      await new Promise(resolve => setTimeout(resolve, 100));
      expect(mockOpenRunPanel).not.toHaveBeenCalled();
    });

    test('does not trigger when IDE is open', async () => {
      const user = userEvent.setup();

      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      // IDE is open
      mockSearchParams.set('panel', 'editor');
      mockSearchParams.set('job', 'job-1');

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('fullscreen-ide')).toBeInTheDocument();
      });

      container.focus();

      await user.keyboard('{Meta>}{Enter}{/Meta}');

      await new Promise(resolve => setTimeout(resolve, 100));
      expect(mockOpenRunPanel).not.toHaveBeenCalled();
    });

    test('works in form fields (enableOnFormTags)', async () => {
      const user = userEvent.setup();

      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      // Create and focus a textarea
      const textarea = document.createElement('textarea');
      container.appendChild(textarea);
      textarea.focus();

      // Press Cmd+Enter while textarea is focused
      await user.keyboard('{Meta>}{Enter}{/Meta}');

      await waitFor(() => {
        expect(mockOpenRunPanel).toHaveBeenCalledWith({ jobId: 'job-1' });
      });
    });
  });

  describe('guard conditions', () => {
    test('Cmd+E only works for job nodes', async () => {
      const user = userEvent.setup();

      // Test with job - should work
      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      await user.keyboard('{Control>}e{/Control}');

      await waitFor(() => {
        expect(mockUpdateSearchParams).toHaveBeenCalledWith({
          panel: 'editor',
        });
      });
    });

    test('Mod+Enter disabled when IDE open', async () => {
      const user = userEvent.setup();

      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      mockSearchParams.set('panel', 'editor');
      mockSearchParams.set('job', 'job-1');

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('fullscreen-ide')).toBeInTheDocument();
      });

      container.focus();

      await user.keyboard('{Control>}{Enter}{/Control}');

      await new Promise(resolve => setTimeout(resolve, 100));
      expect(mockOpenRunPanel).not.toHaveBeenCalled();
    });

    test('Mod+Enter disabled when run panel already open', async () => {
      const user = userEvent.setup();

      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      mockIsRunPanelOpen.mockReturnValue(true);
      mockRunPanelContext.mockReturnValue({ jobId: 'job-1' });

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('manual-run-panel')).toBeInTheDocument();
      });

      container.focus();

      await user.keyboard('{Control>}{Enter}{/Control}');

      await new Promise(resolve => setTimeout(resolve, 100));
      expect(mockOpenRunPanel).not.toHaveBeenCalled();
    });
  });

  describe('behavior with different node selections', () => {
    test('Mod+Enter opens run panel for job selection', async () => {
      const user = userEvent.setup();

      // Test with job selection
      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[1],
      };

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      await user.keyboard('{Control>}{Enter}{/Control}');

      await waitFor(() => {
        expect(mockOpenRunPanel).toHaveBeenCalledWith({ jobId: 'job-2' });
      });
    });

    test('Mod+Enter opens run panel for trigger selection', async () => {
      const user = userEvent.setup();

      // Test with trigger selection
      currentNode = {
        type: 'trigger',
        node: mockWorkflow.triggers[1],
      };

      const { container } = renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      container.focus();

      await user.keyboard('{Control>}{Enter}{/Control}');

      await waitFor(() => {
        expect(mockOpenRunPanel).toHaveBeenCalledWith({
          triggerId: 'trigger-2',
        });
      });
    });
  });
});
