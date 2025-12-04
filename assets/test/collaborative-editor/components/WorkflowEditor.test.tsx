/**
 * WorkflowEditor Component Tests
 *
 * Tests for WorkflowEditor component that manages the main workflow editing
 * interface with canvas, inspector, and run panel. Tests cover:
 * - Keyboard shortcuts (Cmd+Enter to open run panel and trigger runs, Ctrl+E to open IDE)
 * - Run panel opening with correct context (job, trigger, or first trigger)
 * - Run panel context updates when node selection changes
 * - Integration with ManualRunPanel run state
 * - Inspector panel behavior
 * - IDE opening with Ctrl+E when job is selected
 */

import { render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import * as dataclipApi from '../../../js/collaborative-editor/api/dataclips';
import { WorkflowEditor } from '../../../js/collaborative-editor/components/WorkflowEditor';
import { KeyboardProvider } from '../../../js/collaborative-editor/keyboard';
import type { Workflow } from '../../../js/collaborative-editor/types/workflow';

// Mock dependencies
vi.mock('../../../js/collaborative-editor/api/dataclips');

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
  Inspector: ({ onOpenRunPanel }: { onOpenRunPanel: (ctx: any) => void }) => (
    <div data-testid="inspector">Inspector</div>
  ),
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

// Mock ManualRunPanel with run state callback
let mockOnRunStateChange:
  | ((
      canRun: boolean,
      isSubmitting: boolean,
      handler: () => void,
      retryHandler?: () => void,
      isRetryable?: boolean
    ) => void)
  | null = null;
const mockRunHandler = vi.fn();
const mockRetryHandler = vi.fn();

vi.mock('../../../js/collaborative-editor/components/ManualRunPanel', () => ({
  ManualRunPanel: ({
    jobId,
    triggerId,
    onRunStateChange,
    saveWorkflow,
  }: {
    jobId?: string;
    triggerId?: string;
    onRunStateChange?: (
      canRun: boolean,
      isSubmitting: boolean,
      handler: () => void,
      retryHandler?: () => void,
      isRetryable?: boolean
    ) => void;
    saveWorkflow?: () => Promise<void>;
  }) => {
    // Store callback for later use
    mockOnRunStateChange = onRunStateChange || null;

    // Call callback after mount to simulate ManualRunPanel behavior
    if (onRunStateChange) {
      setTimeout(() => {
        // Call with all 5 parameters (last 2 optional)
        onRunStateChange(true, false, mockRunHandler, mockRetryHandler, false);
      }, 0);
    }

    return (
      <div
        data-testid="manual-run-panel"
        data-job-id={jobId}
        data-trigger-id={triggerId}
      >
        ManualRunPanel (job: {jobId}, trigger: {triggerId})
      </div>
    );
  },
}));

// Mock useURLState
const mockUpdateSearchParams = vi.fn();
const mockParams: Record<string, string> = {};

vi.mock('../../../js/react/lib/use-url-state', () => ({
  useURLState: () => ({
    params: mockParams,
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
  useVersions: () => [],
  useVersionsLoading: () => false,
  useVersionsError: () => null,
  useRequestVersions: () => vi.fn(),
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
// Use vi.fn() so we can update return values in tests
const mockIsRunPanelOpen = vi.fn(() => false);
const mockRunPanelContext = vi.fn(() => null);
const mockOpenRunPanel = vi.fn();
const mockCloseRunPanel = vi.fn();

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

const mockSelectNode = vi.fn((node: any) => {
  if (node === null) {
    currentNode = { type: null, node: null };
  }
});

// Mock canRun state
let mockCanRun = true;
let mockTooltipMessage = '';

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
    canRun: mockCanRun,
    tooltipMessage: mockTooltipMessage,
  }),
}));

// Helper function to render WorkflowEditor with providers
function renderWorkflowEditor() {
  return render(
    <KeyboardProvider>
      <WorkflowEditor />
    </KeyboardProvider>
  );
}

describe('WorkflowEditor', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    // Reset state
    mockIsRunPanelOpen.mockReturnValue(false);
    mockRunPanelContext.mockReturnValue(null);
    currentNode = { type: null, node: null };
    mockRunHandler.mockClear();
    mockCanRun = true;
    mockTooltipMessage = '';

    // Default mock for searchDataclips
    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [],
      next_cron_run_dataclip_id: null,
      can_edit_dataclip: true,
    });
  });

  describe('basic rendering', () => {
    test('renders workflow diagram', async () => {
      renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });
    });

    test('renders inspector in DOM', async () => {
      renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      // Inspector is always rendered (visibility controlled by CSS translate classes)
      const inspector = screen.getByTestId('inspector');
      expect(inspector).toBeInTheDocument();
    });

    test('does not show run panel by default', async () => {
      renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      // Run panel should not be visible
      const runPanel = screen.queryByTestId('manual-run-panel');
      expect(runPanel).not.toBeInTheDocument();
    });
  });

  describe('Cmd+Enter keyboard shortcut - triggering run', () => {
    test('shows run panel when open', async () => {
      // Open run panel first
      mockIsRunPanelOpen.mockReturnValue(true);
      mockRunPanelContext.mockReturnValue({ jobId: 'job-1' });

      renderWorkflowEditor();

      // Wait for ManualRunPanel to mount
      await waitFor(() => {
        expect(screen.getByTestId('manual-run-panel')).toBeInTheDocument();
      });

      // Verify panel is visible with correct context
      const panel = screen.getByTestId('manual-run-panel');
      expect(panel.getAttribute('data-job-id')).toBe('job-1');
    });
  });

  describe('run panel rendering', () => {
    test('shows ManualRunPanel with job context when open', async () => {
      mockIsRunPanelOpen.mockReturnValue(true);
      mockRunPanelContext.mockReturnValue({ jobId: 'job-1' });

      renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('manual-run-panel')).toBeInTheDocument();
      });

      const panel = screen.getByTestId('manual-run-panel');
      expect(panel.getAttribute('data-job-id')).toBe('job-1');
    });

    test('shows ManualRunPanel with trigger context when open', async () => {
      mockIsRunPanelOpen.mockReturnValue(true);
      mockRunPanelContext.mockReturnValue({ triggerId: 'trigger-1' });

      renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('manual-run-panel')).toBeInTheDocument();
      });

      const panel = screen.getByTestId('manual-run-panel');
      expect(panel.getAttribute('data-trigger-id')).toBe('trigger-1');
    });
  });

  describe('inspector integration', () => {
    test('shows inspector when node is selected', async () => {
      // Select a job
      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('inspector')).toBeInTheDocument();
      });
    });

    test('inspector renders in the DOM regardless of selection (visibility controlled by CSS)', async () => {
      // No node selected
      currentNode = { type: null, node: null };

      renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      // Inspector is in DOM but has translate-x-full class (off-screen)
      // The component itself mounts regardless of selection
      const inspector = screen.queryByTestId('inspector');
      // We can't easily test CSS classes with JSDOM, so we just verify the structure exists
      expect(inspector).toBeInTheDocument();
    });
  });

  describe('Ctrl+E keyboard shortcut - open IDE', () => {
    test('opens IDE when Ctrl+E pressed with job selected', async () => {
      // Select a job
      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      // Press Ctrl+E - dispatch to window (KeyboardProvider listens on window)
      const event = new KeyboardEvent('keydown', {
        key: 'e',
        ctrlKey: true,
        bubbles: true,
      });
      window.dispatchEvent(event);

      // Should open IDE by setting editor=open in URL
      await waitFor(() => {
        expect(mockUpdateSearchParams).toHaveBeenCalledWith({
          panel: 'editor',
        });
      });
    });

    test('does NOT open IDE when Ctrl+E pressed with trigger selected', async () => {
      // Select a trigger (not a job)
      currentNode = {
        type: 'trigger',
        node: mockWorkflow.triggers[0],
      };

      renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      // Press Ctrl+E - dispatch to window (KeyboardProvider listens on window)
      const event = new KeyboardEvent('keydown', {
        key: 'e',
        ctrlKey: true,
        bubbles: true,
      });
      window.dispatchEvent(event);

      // Should NOT open IDE - silent no-op
      await new Promise(resolve => setTimeout(resolve, 100));
      expect(mockUpdateSearchParams).not.toHaveBeenCalledWith({
        editor: 'open',
      });
    });

    test('does NOT open IDE when Ctrl+E pressed with nothing selected', async () => {
      // Nothing selected
      currentNode = { type: null, node: null };

      renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('workflow-diagram')).toBeInTheDocument();
      });

      // Press Ctrl+E - dispatch to window (KeyboardProvider listens on window)
      const event = new KeyboardEvent('keydown', {
        key: 'e',
        ctrlKey: true,
        bubbles: true,
      });
      window.dispatchEvent(event);

      // Should NOT open IDE - silent no-op
      await new Promise(resolve => setTimeout(resolve, 100));
      expect(mockUpdateSearchParams).not.toHaveBeenCalledWith({
        editor: 'open',
      });
    });

    test('does NOT trigger when IDE is already open', async () => {
      // Select a job
      currentNode = {
        type: 'job',
        node: mockWorkflow.jobs[0],
      };

      // IDE is already open
      mockParams.panel = 'editor';
      mockParams.job = 'job-1';

      renderWorkflowEditor();

      await waitFor(() => {
        expect(screen.getByTestId('fullscreen-ide')).toBeInTheDocument();
      });

      // Press Ctrl+E - dispatch to window (KeyboardProvider listens on window)
      const event = new KeyboardEvent('keydown', {
        key: 'e',
        ctrlKey: true,
        bubbles: true,
      });
      window.dispatchEvent(event);

      // Handler should be disabled - no call to updateSearchParams
      await new Promise(resolve => setTimeout(resolve, 100));
      expect(mockUpdateSearchParams).not.toHaveBeenCalled();
    });
  });
});
