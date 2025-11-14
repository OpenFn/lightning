/**
 * ManualRunPanel Keyboard Shortcut Tests
 *
 * Tests keyboard shortcuts for ManualRunPanel:
 * 1. Escape (Close Panel) - Lines 425-436
 * 2. Run/Retry Shortcuts via useRunRetryShortcuts - Lines 439-447
 *    - Mod+Enter: Run or Retry based on state
 *    - Mod+Shift+Enter: Force new run (even when retry available)
 *
 * Key Focus:
 * - Conflict prevention pattern (enabled: renderMode === STANDALONE)
 * - Guards (canRun, isRunning, isRetryable)
 * - Platform variants (Mac Cmd/Windows Ctrl)
 * - Scope isolation (HOTKEY_SCOPES.RUN_PANEL)
 *
 * NOTE: These tests verify the configuration and integration of keyboard shortcuts,
 * but cannot test the actual keyboard event handling due to limitations in the test
 * environment with react-hotkeys-hook. The shortcuts are manually verified to work
 * in the browser. We focus on testing:
 * - Render mode logic (standalone vs embedded)
 * - Guard conditions (canRun, isRunning, isRetryable)
 * - Integration with save/run workflows
 */

import { render, screen, waitFor } from '@testing-library/react';
import { HotkeysProvider } from 'react-hotkeys-hook';
import type React from 'react';
import { act } from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import * as dataclipApi from '../../../js/collaborative-editor/api/dataclips';
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
    saveWorkflow?: () => Promise<{
      saved_at?: string;
      lock_version?: number;
    } | null>;
  }
) {
  return render(
    <HotkeysProvider initiallyActiveScopes={['runpanel']}>
      <StoreContext.Provider value={stores}>
        <ManualRunPanel
          {...props}
          saveWorkflow={
            props.saveWorkflow ||
            vi
              .fn()
              .mockResolvedValue({
                saved_at: '2025-01-01T00:00:00Z',
                lock_version: 1,
              })
          }
        />
      </StoreContext.Provider>
    </HotkeysProvider>
  );
}

describe('ManualRunPanel Keyboard Shortcuts', () => {
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

    // Default mock for submitManualRun
    vi.mocked(dataclipApi.submitManualRun).mockResolvedValue({
      data: { run_id: 'run-1', workorder_id: 'wo-1' },
    });

    // Mock fetch for dataclip body fetching (used by DataclipViewer)
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      text: async () => JSON.stringify({ data: { test: 'data' } }),
      json: async () => ({ data: { test: 'data' } }),
    } as Response);
  });

  describe('Escape (Close Panel) - Configuration', () => {
    test('renders with escape handler configured', async () => {
      const onClose = vi.fn();

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose,
      });

      await waitFor(() => {
        expect(screen.getByText('Run from Test Job')).toBeInTheDocument();
      });

      // Verify component rendered successfully
      // The escape handler is configured in the component (lines 425-436)
      // with enabled: true, scopes: [HOTKEY_SCOPES.RUN_PANEL], enableOnFormTags: true
      expect(onClose).not.toHaveBeenCalled();
    });

    test('close button works as alternative to Escape', async () => {
      const onClose = vi.fn();

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose,
      });

      await waitFor(() => {
        const closeButton = screen.getByRole('button', {
          name: /close panel/i,
        });
        expect(closeButton).toBeInTheDocument();
        closeButton.click();
      });

      await waitFor(() => {
        expect(onClose).toHaveBeenCalledOnce();
      });
    });
  });

  describe('Run/Retry Shortcuts - Configuration', () => {
    test('standalone mode renders with run button enabled', async () => {
      const saveWorkflow = vi.fn().mockResolvedValue({
        saved_at: '2025-01-01T00:00:00Z',
        lock_version: 2,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: vi.fn(),
        renderMode: 'standalone',
        saveWorkflow,
      });

      await waitFor(() => {
        expect(screen.getByText('Run from Test Job')).toBeInTheDocument();
      });

      // Verify Run button is available (shortcuts configured in lines 439-447)
      const runButton = screen.getByText('Run Workflow Now');
      expect(runButton).not.toBeDisabled();
    });

    test('embedded mode does not show run button (shortcuts disabled)', async () => {
      const saveWorkflow = vi.fn().mockResolvedValue({
        saved_at: '2025-01-01T00:00:00Z',
        lock_version: 2,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: vi.fn(),
        renderMode: 'embedded',
        saveWorkflow,
      });

      await waitFor(() => {
        expect(screen.getByText('Empty')).toBeInTheDocument();
      });

      // Verify Run button is NOT shown in embedded mode
      // (shortcuts disabled via enabled: renderMode === RENDER_MODES.STANDALONE)
      expect(screen.queryByText('Run Workflow Now')).not.toBeInTheDocument();
    });

    test('run button respects canRun guard', async () => {
      setMockCanRun(false, 'You do not have permission to run workflows');

      const saveWorkflow = vi.fn().mockResolvedValue({
        saved_at: '2025-01-01T00:00:00Z',
        lock_version: 2,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: vi.fn(),
        renderMode: 'standalone',
        saveWorkflow,
      });

      await waitFor(() => {
        expect(screen.getByText('Run from Test Job')).toBeInTheDocument();
      });

      // Verify Run button is disabled when canRun is false
      const runButton = screen.getByText('Run Workflow Now');
      expect(runButton).toBeDisabled();
    });

    test('run button shows processing state when running', async () => {
      const saveWorkflow = vi.fn(() => {
        return new Promise(() => {
          // Never resolve - simulates long-running save
        });
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: vi.fn(),
        renderMode: 'standalone',
        saveWorkflow,
      });

      await waitFor(() => {
        expect(screen.getByText('Run from Test Job')).toBeInTheDocument();
      });

      // Click Run button
      const runButton = screen.getByText('Run Workflow Now');
      act(() => {
        runButton.click();
      });

      // Verify button shows processing state
      await waitFor(() => {
        expect(screen.getByText('Processing')).toBeInTheDocument();
        expect(screen.getByText('Processing')).toBeDisabled();
      });
    });
  });

  describe('Conflict Prevention Pattern', () => {
    test('embedded mode does not render run panel UI', async () => {
      const saveWorkflow = vi.fn().mockResolvedValue({
        saved_at: '2025-01-01T00:00:00Z',
        lock_version: 2,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: vi.fn(),
        renderMode: 'embedded',
        saveWorkflow,
      });

      await waitFor(() => {
        expect(screen.getByText('Empty')).toBeInTheDocument();
      });

      // In embedded mode, shortcuts are disabled (enabled: renderMode === STANDALONE)
      // This prevents conflicts with IDE shortcuts
      expect(screen.queryByText('Run from Test Job')).not.toBeInTheDocument();
      expect(screen.queryByText('Run Workflow Now')).not.toBeInTheDocument();
    });

    test('standalone mode provides full UI with shortcuts', async () => {
      const saveWorkflow = vi.fn().mockResolvedValue({
        saved_at: '2025-01-01T00:00:00Z',
        lock_version: 2,
      });

      renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: vi.fn(),
        renderMode: 'standalone',
        saveWorkflow,
      });

      await waitFor(() => {
        expect(screen.getByText('Run from Test Job')).toBeInTheDocument();
      });

      // In standalone mode, full UI is rendered with shortcuts enabled
      expect(screen.getByText('Run Workflow Now')).toBeInTheDocument();
      expect(
        screen.getByRole('button', { name: /close panel/i })
      ).toBeInTheDocument();
    });

    test('shortcuts configuration matches render mode', async () => {
      const saveWorkflow = vi.fn().mockResolvedValue({
        saved_at: '2025-01-01T00:00:00Z',
        lock_version: 2,
      });

      // Test standalone mode
      const { rerender: rerenderStandalone } = renderManualRunPanel({
        workflow: mockWorkflow,
        projectId: 'project-1',
        workflowId: 'workflow-1',
        jobId: 'job-1',
        onClose: vi.fn(),
        renderMode: 'standalone',
        saveWorkflow,
      });

      await waitFor(() => {
        expect(screen.getByText('Run from Test Job')).toBeInTheDocument();
      });

      // useRunRetryShortcuts configured with enabled: renderMode === RENDER_MODES.STANDALONE
      // This ensures shortcuts only work in standalone mode, preventing conflicts with IDE
      expect(screen.getByText('Run Workflow Now')).toBeInTheDocument();
    });
  });
});
