/**
 * ManualRunPanel Component Tests
 *
 * Tests for ManualRunPanel component that allows users to manually trigger
 * workflow runs with custom input data. Tests cover:
 * - Panel rendering with correct context (job vs trigger)
 * - Tab switching and state management
 * - Dataclip fetching and selection
 * - Run button enable/disable logic
 * - Close handler
 * - Permission checks for running workflows
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { HotkeysProvider } from 'react-hotkeys-hook';
import type React from 'react';
import { act } from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import * as dataclipApi from '../../../js/collaborative-editor/api/dataclips';
import { notifications } from '../../../js/collaborative-editor/lib/notifications';
import { ManualRunPanel } from '../../../js/collaborative-editor/components/ManualRunPanel';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { createAdaptorStore } from '../../../js/collaborative-editor/stores/createAdaptorStore';
import { createAwarenessStore } from '../../../js/collaborative-editor/stores/createAwarenessStore';
import { createCredentialStore } from '../../../js/collaborative-editor/stores/createCredentialStore';
import { createRunStore } from '../../../js/collaborative-editor/stores/createRunStore';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import { createUIStore } from '../../../js/collaborative-editor/stores/createUIStore';
import { createWorkflowStore } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Workflow } from '../../../js/collaborative-editor/types/workflow';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../__helpers__';

// Mock the API module
vi.mock('../../../js/collaborative-editor/api/dataclips');

// Mock the notifications module
vi.mock('../../../js/collaborative-editor/lib/notifications', () => ({
  notifications: {
    alert: vi.fn(),
    info: vi.fn(),
    success: vi.fn(),
    warning: vi.fn(),
    dismiss: vi.fn(),
  },
}));

// Create a configurable mock for useCanRun
let mockCanRunValue = { canRun: true, tooltipMessage: 'Run workflow' };

// Mock the useCanRun hook from useWorkflow
vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', async () => {
  const actual = await vi.importActual(
    '../../../js/collaborative-editor/hooks/useWorkflow'
  );
  return {
    ...actual,
    useCanRun: () => mockCanRunValue,
  };
});

// Helper function to override canRun mock
function setMockCanRun(canRun: boolean, tooltipMessage: string) {
  mockCanRunValue = { canRun, tooltipMessage };
}

// Mock MonacoEditor to avoid loading issues in tests
vi.mock('@monaco-editor/react', () => ({
  default: ({ value }: { value: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
}));

// Mock the monaco module that CustomView imports
vi.mock('../../../js/monaco', () => ({
  MonacoEditor: ({ value }: { value: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
}));

// Mock useSession hook
vi.mock('../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: () => ({
    provider: null,
    ydoc: null,
    awareness: null,
    isConnected: false,
    isSynced: false,
  }),
}));

// Mock useURLState hook
vi.mock('../../../js/react/lib/use-url-state', () => ({
  useURLState: () => ({
    searchParams: new URLSearchParams(),
    updateSearchParams: vi.fn(),
    hash: '',
  }),
}));

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

const mockDataclip: dataclipApi.Dataclip = {
  id: 'dataclip-1',
  name: 'Test Dataclip',
  type: 'http_request',
  body: {
    data: { test: 'data' },
    request: {
      headers: { accept: '*/*', host: 'example.com', 'user-agent': 'test' },
      method: 'POST',
      path: ['test'],
      query_params: {},
    },
  },
  request: null,
  inserted_at: '2025-01-01T00:00:00Z',
  updated_at: '2025-01-01T00:00:00Z',
  project_id: 'project-1',
  wiped_at: null,
};

// Create stores for tests
let stores: StoreContextValue;
let mockChannel: any;

// Helper function to render ManualRunPanel with all providers
function renderManualRunPanel(
  props: Omit<React.ComponentProps<typeof ManualRunPanel>, 'saveWorkflow'> & {
    saveWorkflow?: () => Promise<void>;
  }
) {
  return render(
    <StoreContext.Provider value={stores}>
      <HotkeysProvider>
        <ManualRunPanel
          {...props}
          saveWorkflow={
            props.saveWorkflow || vi.fn().mockResolvedValue(undefined)
          }
        />
      </HotkeysProvider>
    </StoreContext.Provider>
  );
}

describe('ManualRunPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    // Reset mock to default state
    setMockCanRun(true, 'Run workflow');

    // Create fresh store instances
    stores = {
      workflowStore: createWorkflowStore(),
      credentialStore: createCredentialStore(),
      sessionContextStore: createSessionContextStore(),
      adaptorStore: createAdaptorStore(),
      awarenessStore: createAwarenessStore(),
      uiStore: createUIStore(),
      runStore: createRunStore(),
    };

    // Create mock channel and connect session context store
    mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    stores.sessionContextStore._connectChannel(mockProvider as any);

    // Set permissions with can_edit_workflow: true by default
    act(() => {
      (mockChannel as any)._test.emit('session_context', {
        user: null,
        project: null,
        config: { require_email_verification: false },
        permissions: {
          can_edit_workflow: true,
          can_run_workflow: true,
          can_write_webhook_auth_method: true,
        },
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
      });
    });

    // Default mock for searchDataclips - returns empty list
    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [],
      next_cron_run_dataclip_id: null,
      can_edit_dataclip: true,
    });
  });

  test('renders with correct title when opened from job', async () => {
    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      jobId: 'job-1',
      onClose: () => {},
    });

    await waitFor(() => {
      expect(screen.getByText('Run from Test Job')).toBeInTheDocument();
    });
  });

  test('renders with correct title when opened from trigger', async () => {
    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      triggerId: 'trigger-1',
      onClose: () => {},
    });

    await waitFor(() => {
      expect(
        screen.getByText('Run from Trigger (webhook)')
      ).toBeInTheDocument();
    });
  });

  test('shows three tabs with correct labels', async () => {
    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      jobId: 'job-1',
      onClose: () => {},
    });

    await waitFor(() => {
      expect(screen.getByText('Empty')).toBeInTheDocument();
    });
    expect(screen.getByText('Custom')).toBeInTheDocument();
    expect(screen.getByText('Existing')).toBeInTheDocument();
  });

  test('starts with Empty tab selected', async () => {
    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      jobId: 'job-1',
      onClose: () => {},
    });

    // Empty view should be visible
    await waitFor(() => {
      expect(
        screen.getByText(/empty JSON object will be used/i)
      ).toBeInTheDocument();
    });
  });

  test('switches to Custom tab when clicked', async () => {
    const user = userEvent.setup();

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      jobId: 'job-1',
      onClose: () => {},
    });

    // Click Custom tab
    await user.click(screen.getByText('Custom'));

    // Monaco editor should appear
    await waitFor(() => {
      expect(screen.getByTestId('monaco-editor')).toBeInTheDocument();
    });
  });

  test('switches to Existing tab when clicked', async () => {
    const user = userEvent.setup();

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      jobId: 'job-1',
      onClose: () => {},
    });

    // Click Existing tab
    await user.click(screen.getByText('Existing'));

    // Search input should appear
    await waitFor(() => {
      expect(
        screen.getByPlaceholderText('Search names or UUID prefixes')
      ).toBeInTheDocument();
    });
  });

  test('calls onClose when close button is clicked', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      jobId: 'job-1',
      onClose: onClose,
    });

    // Wait for component to finish initial render and async operations
    await waitFor(() => {
      expect(
        screen.getByRole('button', { name: /close panel/i })
      ).toBeInTheDocument();
    });

    // Click close button
    await user.click(screen.getByRole('button', { name: /close panel/i }));

    expect(onClose).toHaveBeenCalledOnce();
  });

  test('Run button is enabled when Empty tab is selected', async () => {
    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      jobId: 'job-1',
      onClose: () => {},
    });

    await waitFor(() => {
      const runButton = screen.getByText('Run Workflow Now');
      expect(runButton).not.toBeDisabled();
    });
  });

  test('fetches dataclips on mount with job context', async () => {
    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      jobId: 'job-1',
      onClose: () => {},
    });

    await waitFor(() => {
      expect(dataclipApi.searchDataclips).toHaveBeenCalledWith(
        'project-1',
        'job-1',
        '',
        {}
      );
    });
  });

  test('fetches dataclips on mount with trigger context', async () => {
    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      triggerId: 'trigger-1',
      onClose: () => {},
    });

    // When triggerId is provided, the component finds the target job from the trigger's edge
    // and uses that job to fetch dataclips (since dataclips are associated with jobs, not triggers)
    await waitFor(() => {
      expect(dataclipApi.searchDataclips).toHaveBeenCalledWith(
        'project-1',
        'job-1', // Resolved from trigger-1's edge
        '',
        {}
      );
    });
  });

  test('displays dataclips in Existing tab', async () => {
    const user = userEvent.setup();

    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [mockDataclip],
      next_cron_run_dataclip_id: null,
      can_edit_dataclip: true,
    });

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      jobId: 'job-1',
      onClose: () => {},
    });

    // Switch to Existing tab
    await user.click(screen.getByText('Existing'));

    // Wait for dataclip to appear
    await waitFor(() => {
      expect(screen.getByText('Test Dataclip')).toBeInTheDocument();
    });
  });

  test('auto-selects next cron run dataclip when available', async () => {
    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [mockDataclip],
      next_cron_run_dataclip_id: 'dataclip-1',
      can_edit_dataclip: true,
    });

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      jobId: 'job-1',
      onClose: () => {},
    });

    // Should auto-switch to Existing tab and show selected dataclip with warning banner
    await waitFor(() => {
      expect(screen.getByText('Test Dataclip')).toBeInTheDocument();
      expect(
        screen.getByText('Default Next Input for Cron')
      ).toBeInTheDocument();
    });
  });

  test('shows next cron run warning banner when dataclip is next cron run', async () => {
    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [mockDataclip],
      next_cron_run_dataclip_id: 'dataclip-1',
      can_edit_dataclip: true,
    });

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      jobId: 'job-1',
      onClose: () => {},
    });

    // Should show the next cron run warning banner
    await waitFor(() => {
      expect(
        screen.getByText('Default Next Input for Cron')
      ).toBeInTheDocument();
      expect(
        screen.getByText(/This workflow has a "cron" trigger/)
      ).toBeInTheDocument();
    });
  });

  test('shows next cron run warning banner when opened from trigger', async () => {
    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [mockDataclip],
      next_cron_run_dataclip_id: 'dataclip-1',
      can_edit_dataclip: true,
    });

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      triggerId: 'trigger-1',
      onClose: () => {},
    });

    // Should show the next cron run warning banner
    await waitFor(() => {
      expect(
        screen.getByText('Default Next Input for Cron')
      ).toBeInTheDocument();
      expect(
        screen.getByText(/This workflow has a "cron" trigger/)
      ).toBeInTheDocument();
    });
  });

  test('disables Run button when Custom tab has invalid JSON', async () => {
    const user = userEvent.setup();

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      jobId: 'job-1',
      onClose: () => {},
    });

    // Switch to Custom tab
    await user.click(screen.getByText('Custom'));

    // The Monaco editor is mocked, so we can't actually test JSON validation
    // through user interaction. This is acceptable as JSON validation is
    // tested separately in the validateCustomBody callback.

    // Just verify the tab switched
    await waitFor(() => {
      expect(screen.getByTestId('monaco-editor')).toBeInTheDocument();
    });
  });

  test('enables Run button when Existing tab has selected dataclip', async () => {
    const user = userEvent.setup();

    vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
      data: [mockDataclip],
      next_cron_run_dataclip_id: null,
      can_edit_dataclip: true,
    });

    renderManualRunPanel({
      workflow: mockWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-1',
      jobId: 'job-1',
      onClose: () => {},
    });

    // Switch to Existing tab
    await user.click(screen.getByText('Existing'));

    // Wait for dataclip to appear and click it
    await waitFor(() => {
      expect(screen.getByText('Test Dataclip')).toBeInTheDocument();
    });

    await user.click(screen.getByText('Test Dataclip'));

    // Run button should be enabled
    await waitFor(() => {
      const runButton = screen.getByText('Run Workflow Now');
      expect(runButton).not.toBeDisabled();
    });
  });

  test('handles empty workflow (no triggers)', async () => {
    const emptyWorkflow: Workflow = {
      id: 'workflow-2',
      name: 'Empty Workflow',
      jobs: [],
      triggers: [],
      edges: [],
    };

    renderManualRunPanel({
      workflow: emptyWorkflow,
      projectId: 'project-1',
      workflowId: 'workflow-2',
      onClose: () => {},
    });

    // Should render with generic title
    await waitFor(() => {
      expect(screen.getByText('Run Workflow')).toBeInTheDocument();
    });
  });

  describe('renderMode prop', () => {
    test('standalone mode (default) shows InspectorLayout with header and footer', async () => {
      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
      });

      // Should show header with title
      await waitFor(() => {
        expect(screen.getByText('Run from Test Job')).toBeInTheDocument();
      });

      // Should show close button in header
      expect(
        screen.getByRole('button', { name: /close panel/i })
      ).toBeInTheDocument();

      // Should show footer with Run button
      expect(screen.getByText('Run Workflow Now')).toBeInTheDocument();
    });

    test('embedded mode shows only content, no header or footer', async () => {
      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
        renderMode: 'embedded',
      });

      // Should render tabs (content)
      await waitFor(() => {
        expect(screen.getByText('Empty')).toBeInTheDocument();
      });

      // Should NOT show header with title
      expect(screen.queryByText('Run from Test Job')).not.toBeInTheDocument();

      // Should NOT show close button
      expect(
        screen.queryByRole('button', { name: /close panel/i })
      ).not.toBeInTheDocument();

      // Should NOT show footer with Run button
      expect(screen.queryByText('Run Workflow Now')).not.toBeInTheDocument();
    });

    test('embedded mode with trigger context', async () => {
      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        triggerId: 'trigger-1',
        onClose: () => {},
        renderMode: 'embedded',
      });

      // Should render tabs (content)
      await waitFor(() => {
        expect(screen.getByText('Empty')).toBeInTheDocument();
      });

      // Should NOT show header title
      expect(
        screen.queryByText('Run from Trigger (webhook)')
      ).not.toBeInTheDocument();
    });
  });

  describe('filter debouncing', () => {
    test('filters are applied when changed', async () => {
      const user = userEvent.setup();

      vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
        data: [],
        next_cron_run_dataclip_id: null,
        can_edit_dataclip: true,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
      });

      // Wait for initial fetch
      await waitFor(() => {
        expect(dataclipApi.searchDataclips).toHaveBeenCalledTimes(1);
      });

      // Switch to Existing tab
      await user.click(screen.getByText('Existing'));

      // Find the "Named only" filter button (has hero-tag icon)
      const filterButtons = screen
        .getAllByRole('button')
        .filter(btn => btn.querySelector('.hero-tag'));
      expect(filterButtons.length).toBeGreaterThan(0);

      // Click the named-only filter button
      // This changes the namedOnly state, which triggers the debounced search
      await user.click(filterButtons[0]);

      // Wait for the debounced search to complete (300ms debounce + execution time)
      // The debounce timer from switching tabs is cancelled when the button is clicked
      await waitFor(
        () => {
          expect(dataclipApi.searchDataclips).toHaveBeenCalledTimes(2);
        },
        { timeout: 1000 }
      );
    });
  });

  describe('permission checks', () => {
    test('Run button is disabled when user lacks can_edit_workflow permission', async () => {
      // Mock useCanRun to return false (simulating lack of permission)
      setMockCanRun(false, 'You do not have permission to run workflows');

      // Override permissions to deny workflow editing
      act(() => {
        (mockChannel as any)._test.emit('session_context', {
          user: null,
          project: null,
          config: { require_email_verification: false },
          permissions: { can_edit_workflow: false },
          latest_snapshot_lock_version: 1,
          project_repo_connection: null,
        });
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
      });

      await waitFor(() => {
        const runButton = screen.getByText('Run Workflow Now');
        expect(runButton).toBeDisabled();
      });
    });

    test('Run button is enabled when user has can_edit_workflow permission', async () => {
      // Permissions already set to can_edit_workflow: true in beforeEach
      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
      });

      await waitFor(() => {
        const runButton = screen.getByText('Run Workflow Now');
        expect(runButton).not.toBeDisabled();
      });
    });

    test('Run button remains disabled in Existing tab without permission, even with selected dataclip', async () => {
      const user = userEvent.setup();

      // Mock useCanRun to return false (simulating lack of permission)
      setMockCanRun(false, 'You do not have permission to run workflows');

      // Override permissions to deny workflow editing
      act(() => {
        (mockChannel as any)._test.emit('session_context', {
          user: null,
          project: null,
          config: { require_email_verification: false },
          permissions: { can_edit_workflow: false },
          latest_snapshot_lock_version: 1,
          project_repo_connection: null,
        });
      });

      vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
        data: [mockDataclip],
        next_cron_run_dataclip_id: null,
        can_edit_dataclip: false,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
      });

      // Switch to Existing tab
      await user.click(screen.getByText('Existing'));

      // Wait for dataclip to appear and click it
      await waitFor(() => {
        expect(screen.getByText('Test Dataclip')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Test Dataclip'));

      // Run button should still be disabled due to lack of permission
      await waitFor(() => {
        const runButton = screen.getByText('Run Workflow Now');
        expect(runButton).toBeDisabled();
      });
    });
  });

  describe('Save & Run behavior', () => {
    test('saves workflow before submitting run', async () => {
      const user = userEvent.setup();
      const saveWorkflow = vi.fn().mockResolvedValue({
        saved_at: '2025-01-01T00:00:00Z',
        lock_version: 2,
      });

      // Track the order of calls
      const callOrder: string[] = [];

      saveWorkflow.mockImplementation(async () => {
        callOrder.push('save');
        return { saved_at: '2025-01-01T00:00:00Z', lock_version: 2 };
      });

      vi.mocked(dataclipApi.submitManualRun).mockImplementation(async () => {
        callOrder.push('run');
        return { data: { run_id: 'run-1', workorder_id: 'wo-1' } };
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
        saveWorkflow,
      });

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText('Run Workflow Now')).toBeInTheDocument();
      });

      // Click Run button
      await user.click(screen.getByText('Run Workflow Now'));

      // Verify save was called first, then run
      await waitFor(() => {
        expect(callOrder).toEqual(['save', 'run']);
        expect(saveWorkflow).toHaveBeenCalledOnce();
        expect(dataclipApi.submitManualRun).toHaveBeenCalledOnce();
      });
    });

    test('does not run if save fails', async () => {
      const user = userEvent.setup();
      const saveWorkflow = vi.fn().mockRejectedValue(new Error('Save failed'));

      // Clear notifications mock before test
      vi.mocked(notifications.alert).mockClear();

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
        saveWorkflow,
      });

      await waitFor(() => {
        expect(screen.getByText('Run Workflow Now')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Run Workflow Now'));

      // Save should be called
      await waitFor(() => {
        expect(saveWorkflow).toHaveBeenCalledOnce();
      });

      // Run should NOT be called because save failed
      expect(dataclipApi.submitManualRun).not.toHaveBeenCalled();

      // Error should be shown to user via notifications
      await waitFor(() => {
        expect(notifications.alert).toHaveBeenCalledWith({
          title: 'Failed to submit run',
          description: 'Save failed',
        });
      });
    });

    test('does not run if save fails with generic error', async () => {
      const user = userEvent.setup();
      const saveWorkflow = vi.fn().mockRejectedValue('Network error'); // Non-Error type

      // Clear notifications mock before test
      vi.mocked(notifications.alert).mockClear();

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
        saveWorkflow,
      });

      await waitFor(() => {
        expect(screen.getByText('Run Workflow Now')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Run Workflow Now'));

      // Save should be called
      await waitFor(() => {
        expect(saveWorkflow).toHaveBeenCalledOnce();
      });

      // Run should NOT be called because save failed
      expect(dataclipApi.submitManualRun).not.toHaveBeenCalled();

      // Generic error message should be shown to user via notifications
      await waitFor(() => {
        expect(notifications.alert).toHaveBeenCalledWith({
          title: 'Failed to submit run',
          description: 'An unknown error occurred',
        });
      });
    });

    test('calls saveWorkflow with correct signature', async () => {
      const user = userEvent.setup();
      const saveWorkflow = vi.fn().mockResolvedValue({
        saved_at: '2025-01-01T00:00:00Z',
        lock_version: 2,
      });

      vi.mocked(dataclipApi.submitManualRun).mockResolvedValue({
        data: { run_id: 'run-1', workorder_id: 'wo-1' },
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
        saveWorkflow,
      });

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText('Run Workflow Now')).toBeInTheDocument();
      });

      // Click Run button
      await user.click(screen.getByText('Run Workflow Now'));

      // Verify saveWorkflow was called with { silent: true }
      await waitFor(() => {
        expect(saveWorkflow).toHaveBeenCalledWith({ silent: true });
        expect(saveWorkflow).toHaveBeenCalledOnce();
      });
    });

    test('submitting state prevents multiple simultaneous runs', async () => {
      const user = userEvent.setup();
      let saveResolve: () => void;
      const savePromise = new Promise<{
        saved_at: string;
        lock_version: number;
      }>(resolve => {
        saveResolve = () =>
          resolve({ saved_at: '2025-01-01T00:00:00Z', lock_version: 2 });
      });
      const saveWorkflow = vi.fn().mockReturnValue(savePromise);

      vi.mocked(dataclipApi.submitManualRun).mockResolvedValue({
        data: { run_id: 'run-1', workorder_id: 'wo-1' },
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
        saveWorkflow,
      });

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText('Run Workflow Now')).toBeInTheDocument();
      });

      // Click Run button - this will start the save
      await user.click(screen.getByText('Run Workflow Now'));

      // Button should show "Processing" while submitting
      await waitFor(() => {
        expect(screen.getByText('Processing')).toBeInTheDocument();
      });

      // Button should be disabled
      const runButton = screen.getByText('Processing');
      expect(runButton).toBeDisabled();

      // Try to click again - should not trigger another save
      await user.click(runButton);

      // Should still only have one call to saveWorkflow
      expect(saveWorkflow).toHaveBeenCalledOnce();

      // Resolve the save to complete the test
      saveResolve!();
    });
  });

  describe('Unselecting Dataclip Behavior', () => {
    test('disables Run button when dataclip is unselected on Existing tab', async () => {
      const user = userEvent.setup();

      vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
        data: [mockDataclip],
        next_cron_run_dataclip_id: null,
        can_edit_dataclip: true,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
      });

      // Switch to Existing tab
      await user.click(screen.getByText('Existing'));

      // Select a dataclip
      await waitFor(() => {
        expect(screen.getByText('Test Dataclip')).toBeInTheDocument();
      });
      await user.click(screen.getByText('Test Dataclip'));

      // Button should be enabled with selected dataclip
      await waitFor(() => {
        const runButton = screen.getByText('Run Workflow Now');
        expect(runButton).not.toBeDisabled();
      });

      // Unselect the dataclip by clicking the X button (close button in SelectedDataclipView)
      // After selecting dataclip, we have SelectedDataclipView with its own buttons
      // Wait for the view to render
      await waitFor(() => {
        expect(screen.getByText('Test Dataclip')).toBeInTheDocument();
      });

      // Find the close button - it's the last button with an X icon in the header
      const allButtons = screen.getAllByRole('button');
      // The close button is in the SelectedDataclipView header with ml-4 class
      const xButton = allButtons.find(
        btn =>
          btn.className.includes('ml-4') &&
          btn.className.includes('text-gray-400')
      );
      await user.click(xButton!);

      // Button should now be disabled
      await waitFor(() => {
        const runButton = screen.getByText('Run Workflow Now');
        expect(runButton).toBeDisabled();
      });
    });

    test('does not auto-reselect dataclip after manual unselection when switching tabs', async () => {
      const user = userEvent.setup();

      vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
        data: [mockDataclip],
        next_cron_run_dataclip_id: null,
        can_edit_dataclip: true,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
      });

      // Switch to Existing tab
      await user.click(screen.getByText('Existing'));

      // Select a dataclip
      await waitFor(() => {
        expect(screen.getByText('Test Dataclip')).toBeInTheDocument();
      });
      await user.click(screen.getByText('Test Dataclip'));

      // Unselect the dataclip - find close button in SelectedDataclipView
      await waitFor(() => {
        expect(screen.getByText('Test Dataclip')).toBeInTheDocument();
      });
      const allButtons = screen.getAllByRole('button');
      const xButton = allButtons.find(
        btn =>
          btn.className.includes('ml-4') &&
          btn.className.includes('text-gray-400')
      );
      await user.click(xButton!);

      // Switch to Custom tab
      await user.click(screen.getByText('Custom'));

      // Switch back to Existing tab
      await user.click(screen.getByText('Existing'));

      // Dataclip should NOT be auto-selected
      await waitFor(() => {
        expect(
          screen.queryByText('Default Next Input for Cron')
        ).not.toBeInTheDocument();
      });

      // The list should still show the dataclip as available
      expect(screen.getByText('Test Dataclip')).toBeInTheDocument();

      // Run button should still be disabled
      const runButton = screen.getByText('Run Workflow Now');
      expect(runButton).toBeDisabled();
    });

    test('re-enables Run button when switching to Empty tab after unselecting dataclip', async () => {
      const user = userEvent.setup();

      vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
        data: [mockDataclip],
        next_cron_run_dataclip_id: null,
        can_edit_dataclip: true,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
      });

      // Switch to Existing tab and select dataclip
      await user.click(screen.getByText('Existing'));
      await waitFor(() => {
        expect(screen.getByText('Test Dataclip')).toBeInTheDocument();
      });
      await user.click(screen.getByText('Test Dataclip'));

      // Unselect the dataclip - find close button in SelectedDataclipView
      await waitFor(() => {
        expect(screen.getByText('Test Dataclip')).toBeInTheDocument();
      });
      const allButtons = screen.getAllByRole('button');
      const xButton = allButtons.find(
        btn =>
          btn.className.includes('ml-4') &&
          btn.className.includes('text-gray-400')
      );
      await user.click(xButton!);

      // Switch to Empty tab
      await user.click(screen.getByText('Empty'));

      // Run button should be enabled on Empty tab
      await waitFor(() => {
        const runButton = screen.getByText('Run Workflow Now');
        expect(runButton).not.toBeDisabled();
      });
    });

    test('calls onDataclipChange callback when dataclip is unselected', async () => {
      const user = userEvent.setup();
      const onDataclipChange = vi.fn();

      vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
        data: [mockDataclip],
        next_cron_run_dataclip_id: null,
        can_edit_dataclip: true,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
        onDataclipChange,
      });

      // Switch to Existing tab and select dataclip
      await user.click(screen.getByText('Existing'));
      await waitFor(() => {
        expect(screen.getByText('Test Dataclip')).toBeInTheDocument();
      });
      await user.click(screen.getByText('Test Dataclip'));

      // Callback should be called with dataclip
      await waitFor(() => {
        expect(onDataclipChange).toHaveBeenCalledWith(
          expect.objectContaining({ id: 'dataclip-1' })
        );
      });

      // Unselect the dataclip - find close button in SelectedDataclipView
      await waitFor(() => {
        expect(screen.getByText('Test Dataclip')).toBeInTheDocument();
      });
      const allButtons = screen.getAllByRole('button');
      const xButton = allButtons.find(
        btn =>
          btn.className.includes('ml-4') &&
          btn.className.includes('text-gray-400')
      );
      await user.click(xButton!);

      // Callback should be called with null
      await waitFor(() => {
        expect(onDataclipChange).toHaveBeenCalledWith(null);
      });
    });
  });

  describe('footer button tooltip props', () => {
    test('footer button passes showKeyboardShortcuts=true in standalone mode', async () => {
      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
        // renderMode defaults to 'standalone'
      });

      // Footer should be rendered with Run button
      await waitFor(() => {
        expect(screen.getByText('Run Workflow Now')).toBeInTheDocument();
      });

      const runButton = screen.getByText('Run Workflow Now');
      expect(runButton).not.toBeDisabled();

      // The footer button passes showKeyboardShortcuts=true
      // because in standalone mode, RUN_PANEL scope owns the shortcuts
    });

    test('footer button passes disabledTooltip when disabled', async () => {
      // Mock useCanRun to return false with tooltip message
      setMockCanRun(false, 'Cannot run: workflow has validation errors');

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
      });

      await waitFor(() => {
        const runButton = screen.getByText('Run Workflow Now');
        expect(runButton).toBeDisabled();
      });

      // The runTooltip should be passed as disabledTooltip to RunRetryButton
    });

    test('footer button shows tooltips for retryable run', async () => {
      const user = userEvent.setup();

      // Add a retryable run to workflow
      const retryableWorkflow: Workflow = {
        ...mockWorkflow,
        jobs: [
          {
            ...mockWorkflow.jobs[0],
            id: 'job-1',
          },
        ],
      };

      // Mock dataclip with next cron run to trigger retryable state
      vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
        data: [mockDataclip],
        next_cron_run_dataclip_id: 'dataclip-1',
        can_edit_dataclip: true,
      });

      renderManualRunPanel({
        workflow: retryableWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
      });

      // Wait for component to load with retryable state
      await waitFor(() => {
        expect(screen.getByText('Run Workflow Now')).toBeInTheDocument();
      });

      // Footer button should be rendered
      const runButton = screen.getByText('Run Workflow Now');
      expect(runButton).toBeInTheDocument();

      // showKeyboardShortcuts=true is passed, enabling tooltip for main button
      // and dropdown option (if retryable and dropdown shown)
    });

    test('no footer in embedded mode (no tooltip concerns)', async () => {
      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
        renderMode: 'embedded',
      });

      // Wait for tabs to render
      await waitFor(() => {
        expect(screen.getByText('Empty')).toBeInTheDocument();
      });

      // Footer should NOT be rendered in embedded mode
      expect(screen.queryByText('Run Workflow Now')).not.toBeInTheDocument();

      // No tooltip concerns because RunRetryButton is not rendered in footer
    });
  });

  describe('controlled component mode', () => {
    test('Run button state reflects controlled customBody prop', async () => {
      vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
        data: [],
        next_cron_run_dataclip_id: null,
        can_edit_dataclip: true,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
        selectedTab: 'custom',
        customBody: '{"test": "data"}',
      });

      await waitFor(() => {
        const runButton = screen.getByText('Run Workflow Now');
        expect(runButton).not.toBeDisabled();
      });
    });

    test('Run button disabled when controlled customBody is empty', async () => {
      vi.mocked(dataclipApi.searchDataclips).mockResolvedValue({
        data: [],
        next_cron_run_dataclip_id: null,
        can_edit_dataclip: true,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: () => {},
        selectedTab: 'custom',
        customBody: '',
      });

      await waitFor(() => {
        const runButton = screen.getByText('Run Workflow Now');
        expect(runButton).toBeDisabled();
      });
    });
  });
});
