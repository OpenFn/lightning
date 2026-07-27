/**
 * Header Keyboard Shortcut Tests
 *
 * Tests for keyboard shortcuts in the Header component:
 * - Cmd+S / Ctrl+S (Save Workflow)
 * - Cmd+Shift+S / Ctrl+Shift+S (Save & Sync to GitHub)
 *
 * Testing approach:
 * - Library-agnostic (tests user-facing behavior, not implementation)
 * - Platform coverage (Mac Cmd and Windows Ctrl)
 * - Guard conditions (canSave, repoConnection)
 * - Form field support (enableOnFormTags)
 */

import { act, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type React from 'react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import type { RunDetail } from '../../../js/collaborative-editor/types/history';

import { Header } from '../../../js/collaborative-editor/components/Header';
import { SessionContext } from '../../../js/collaborative-editor/contexts/SessionProvider';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { KeyboardProvider } from '../../../js/collaborative-editor/keyboard';
import type { CreateSessionContextOptions } from '../__helpers__/sessionContextFactory';
import { simulateStoreProviderWithConnection } from '../__helpers__/storeProviderHelpers';
import {
  createMockURLState,
  getURLStateMockValue,
} from '../__helpers__/urlStateMocks';
import { createWorkflowYDoc } from '../__helpers__/workflowFactory';
import { createMinimalWorkflowYDoc } from '../__helpers__/workflowStoreHelpers';

// =============================================================================
// TEST MOCKS
// =============================================================================

// Mock useURLState
const urlState = createMockURLState();

vi.mock('../../../js/react/lib/use-url-state', () => ({
  useURLState: () => getURLStateMockValue(urlState),
}));

// Mock useAdaptorIcons to prevent async fetch warnings
vi.mock('../../../js/workflow-diagram/useAdaptorIcons', () => ({
  default: () => ({}),
}));

// Mock Tooltip to prevent Radix UI timer-based updates
vi.mock('../../../js/collaborative-editor/components/Tooltip', () => ({
  Tooltip: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

// Mock dataclipApi so submitManualRun can be spied on
const mockSubmitManualRun = vi.fn();
vi.mock('../../../js/collaborative-editor/api/dataclips', () => ({
  submitManualRun: (...args: unknown[]) => mockSubmitManualRun(...args),
  searchDataclips: vi.fn(() =>
    Promise.resolve({
      data: [],
      next_cron_run_dataclip_id: null,
      can_edit_dataclip: true,
    })
  ),
}));

// =============================================================================
// TEST HELPERS
// =============================================================================

/**
 * Creates a Y.Doc with workflow metadata AND a trigger so firstTriggerId is set.
 * Used by the Cmd+Enter tests which require canRun + firstTriggerId to be truthy.
 */
function createWorkflowYDocWithTrigger(
  lockVersion: number | null = 1
): ReturnType<typeof createWorkflowYDoc> & { triggerId: string } {
  const triggerId = 'trigger-test-1';
  const ydoc = createWorkflowYDoc({
    triggers: {
      [triggerId]: { id: triggerId, type: 'webhook', enabled: true },
    },
  });

  // Merge workflow metadata into the doc (createWorkflowYDoc doesn't set it)
  const workflowMap = ydoc.getMap('workflow');
  workflowMap.set('id', 'test-workflow-123');
  workflowMap.set('name', 'Test Workflow');
  workflowMap.set('lock_version', lockVersion);
  workflowMap.set('deleted_at', null);
  workflowMap.set('concurrency', null);
  workflowMap.set('enable_job_logs', false);

  // createWorkflowYDoc doesn't initialise positions / errors maps
  ydoc.getMap('positions');
  ydoc.getMap('errors');

  return Object.assign(ydoc, { triggerId });
}

interface WrapperOptions {
  permissions?: { can_edit_workflow: boolean; can_run_workflow: boolean };
  latestSnapshotLockVersion?: number;
  workflowLockVersion?: number | null;
  hasGithubConnection?: boolean;
  repoName?: string;
  branchName?: string;
  workflowDeleted?: boolean;
}

async function createTestSetup(options: WrapperOptions = {}) {
  const {
    permissions = { can_edit_workflow: true, can_run_workflow: true },
    latestSnapshotLockVersion = 1,
    workflowLockVersion = 1,
    hasGithubConnection = false,
    repoName = 'openfn/demo',
    branchName = 'main',
    workflowDeleted = false,
  } = options;

  // Create Y.Doc with workflow metadata using helper
  const ydoc = createMinimalWorkflowYDoc(
    'test-workflow-123',
    'Test Workflow',
    workflowLockVersion
  );

  // Set deleted_at if specified
  if (workflowDeleted) {
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('deleted_at', new Date().toISOString());
  }

  // Build session context options
  const sessionContextOptions: CreateSessionContextOptions = {
    permissions,
    latest_snapshot_lock_version: latestSnapshotLockVersion,
  };

  if (hasGithubConnection) {
    sessionContextOptions.project_repo_connection = {
      repo: repoName,
      branch: branchName,
    };
  }

  // Use enhanced helper - THIS HANDLES CONNECTION STATE!
  const { stores, sessionStore, cleanup, emitSessionContext } =
    await simulateStoreProviderWithConnection(
      'test:room',
      {
        id: 'user-1',
        name: 'Test User',
        color: '#ff0000',
      },
      {
        workflowYDoc: ydoc,
        sessionContext: sessionContextOptions,
        emitSessionContext: true,
      }
    );

  // CRITICAL FIX: Manually emit 'sync' event on provider
  // The mock channel doesn't trigger Y.js sync protocol, so provider never emits 'sync'
  // We need to manually trigger it so isSynced becomes true
  const provider = sessionStore.getProvider();
  if (provider) {
    // Emit the 'sync' event with synced=true
    (provider as any).emit('sync', [true]);
  }

  // Wait a bit for the sync event to propagate
  await new Promise(resolve => setTimeout(resolve, 150));

  // Add spies for keyboard test assertions
  const saveWorkflowSpy = vi
    .spyOn(stores.workflowStore, 'saveWorkflow')
    .mockResolvedValue(undefined);
  const openGitHubSyncModalSpy = vi.spyOn(
    stores.uiStore,
    'openGitHubSyncModal'
  );

  // Wrapper with KeyboardProvider (keyboard-specific)
  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <KeyboardProvider>
      <SessionContext.Provider value={{ sessionStore, isNewWorkflow: false }}>
        <StoreContext.Provider value={stores}>{children}</StoreContext.Provider>
      </SessionContext.Provider>
    </KeyboardProvider>
  );

  return {
    wrapper,
    stores,
    sessionStore,
    emitSessionContext,
    saveWorkflowSpy,
    openGitHubSyncModalSpy,
    cleanup,
  };
}

// Helper to render and wait for component to be ready
async function renderAndWaitForReady(
  wrapper: React.ComponentType<{ children: React.ReactNode }>,
  emitSessionContext: () => void
) {
  const result = render(
    <Header projectId="project-1" workflowId="workflow-1">
      {[<span key="breadcrumb-1">Breadcrumb</span>]}
    </Header>,
    { wrapper }
  );

  await act(async () => {
    emitSessionContext();
    await new Promise(resolve => setTimeout(resolve, 150));
  });

  await waitFor(() => {
    const saveButton = screen.getByTestId('save-workflow-button');
    expect(saveButton).toBeInTheDocument();
  });

  return result;
}

// =============================================================================
// SAVE WORKFLOW KEYBOARD SHORTCUT TESTS (Cmd+S / Ctrl+S)
// =============================================================================

describe('Header - Save Workflow (Cmd+S / Ctrl+S)', () => {
  beforeEach(() => {
    urlState.reset();
  });
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(async () => {
    // Wait for any pending async updates to settle after test
    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50));
    });
  });

  test('Cmd+S calls saveWorkflow when canSave is true (Mac)', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, saveWorkflowSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
      });

    const { unmount } = await renderAndWaitForReady(
      wrapper,
      emitSessionContext!
    );

    // Verify the save button is rendered (confirms Header is mounted)
    const saveButton = screen.getByTestId('save-workflow-button');
    expect(saveButton).toBeInTheDocument();

    await user.keyboard('{Meta>}s{/Meta}');

    await waitFor(() => expect(saveWorkflowSpy).toHaveBeenCalledTimes(1));

    unmount();
    cleanup();
  });

  test('Ctrl+S calls saveWorkflow when canSave is true (Windows)', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, saveWorkflowSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
      });

    const { unmount } = await renderAndWaitForReady(
      wrapper,
      emitSessionContext!
    );

    await user.keyboard('{Control>}s{/Control}');

    await waitFor(() => expect(saveWorkflowSpy).toHaveBeenCalledTimes(1));

    unmount();
    cleanup();
  });

  test('Cmd+S does NOT call saveWorkflow when no edit permission', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, saveWorkflowSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: false, can_run_workflow: true },
      });

    const { unmount } = await renderAndWaitForReady(
      wrapper,
      emitSessionContext!
    );

    await user.keyboard('{Meta>}s{/Meta}');

    // Wait to ensure handler doesn't fire
    await new Promise(resolve => setTimeout(resolve, 150));

    expect(saveWorkflowSpy).not.toHaveBeenCalled();

    unmount();
    cleanup();
  });

  test('Cmd+S does NOT call saveWorkflow when workflow is deleted', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, saveWorkflowSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        workflowDeleted: true,
      });

    const { unmount } = await renderAndWaitForReady(
      wrapper,
      emitSessionContext!
    );

    await user.keyboard('{Meta>}s{/Meta}');

    // Wait to ensure handler doesn't fire
    await new Promise(resolve => setTimeout(resolve, 150));

    expect(saveWorkflowSpy).not.toHaveBeenCalled();

    unmount();
    cleanup();
  });

  test('Cmd+S responds to dynamic canSave changes (enable → disable → enable)', async () => {
    const user = userEvent.setup();

    // Start with canSave = true
    const { wrapper, emitSessionContext, saveWorkflowSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
      });

    const { unmount } = await renderAndWaitForReady(
      wrapper,
      emitSessionContext!
    );

    // Phase 1: canSave = true, shortcut should work
    await user.keyboard('{Meta>}s{/Meta}');
    await waitFor(() => expect(saveWorkflowSpy).toHaveBeenCalledTimes(1));

    saveWorkflowSpy.mockClear();

    // Phase 2: Change to canSave = false (simulate permission loss)
    await act(async () => {
      emitSessionContext!({
        permissions: { can_edit_workflow: false, can_run_workflow: true },
      });
      await new Promise(resolve => setTimeout(resolve, 100));
    });

    // Shortcut should NOT work
    await user.keyboard('{Meta>}s{/Meta}');
    await new Promise(resolve => setTimeout(resolve, 150));
    expect(saveWorkflowSpy).not.toHaveBeenCalled();

    // Phase 3: Change back to canSave = true
    await act(async () => {
      emitSessionContext!({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
      });
      await new Promise(resolve => setTimeout(resolve, 100));
    });

    // Shortcut should work again
    await user.keyboard('{Meta>}s{/Meta}');
    await waitFor(() => expect(saveWorkflowSpy).toHaveBeenCalledTimes(1));

    unmount();
    cleanup();
  });

  test('Cmd+S does NOT call saveWorkflow when viewing pinned version', async () => {
    const user = userEvent.setup();

    // Set pinned version in URL
    urlState.setParam('v', '1');

    const { wrapper, emitSessionContext, saveWorkflowSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
      });

    const { unmount } = await renderAndWaitForReady(
      wrapper,
      emitSessionContext!
    );

    await user.keyboard('{Meta>}s{/Meta}');

    // Wait to ensure handler doesn't fire
    await new Promise(resolve => setTimeout(resolve, 150));

    expect(saveWorkflowSpy).not.toHaveBeenCalled();

    unmount();
    cleanup();
  });

  test('Cmd+S works in input fields (enableOnFormTags)', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, saveWorkflowSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
      });

    const { unmount } = render(
      <>
        <input data-testid="test-input" />
        <Header projectId="project-1" workflowId="workflow-1">
          {[<span key="breadcrumb-1">Breadcrumb</span>]}
        </Header>
      </>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext!();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    await waitFor(() => {
      expect(screen.getByTestId('save-workflow-button')).toBeInTheDocument();
    });

    const input = screen.getByTestId('test-input');
    await user.click(input);

    await user.keyboard('{Meta>}s{/Meta}');

    await waitFor(() => expect(saveWorkflowSpy).toHaveBeenCalled());

    unmount();
    cleanup();
  });

  test('Cmd+S works in textarea (enableOnFormTags)', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, saveWorkflowSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
      });

    const { unmount } = render(
      <>
        <textarea data-testid="test-textarea" />
        <Header projectId="project-1" workflowId="workflow-1">
          {[<span key="breadcrumb-1">Breadcrumb</span>]}
        </Header>
      </>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext!();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    await waitFor(() => {
      expect(screen.getByTestId('save-workflow-button')).toBeInTheDocument();
    });

    const textarea = screen.getByTestId('test-textarea');
    await user.click(textarea);

    await user.keyboard('{Meta>}s{/Meta}');

    await waitFor(() => expect(saveWorkflowSpy).toHaveBeenCalled());

    unmount();
    cleanup();
  });

  test('Cmd+S works in select (enableOnFormTags)', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, saveWorkflowSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
      });

    const { unmount } = render(
      <>
        <select data-testid="test-select">
          <option value="1">Option 1</option>
        </select>
        <Header projectId="project-1" workflowId="workflow-1">
          {[<span key="breadcrumb-1">Breadcrumb</span>]}
        </Header>
      </>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext!();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    await waitFor(() => {
      expect(screen.getByTestId('save-workflow-button')).toBeInTheDocument();
    });

    const select = screen.getByTestId('test-select');
    await user.click(select);

    await user.keyboard('{Meta>}s{/Meta}');

    await waitFor(() => expect(saveWorkflowSpy).toHaveBeenCalled());

    unmount();
    cleanup();
  });

  test('Cmd+S works in contentEditable (enableOnFormTags)', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, saveWorkflowSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
      });

    const { unmount } = render(
      <>
        <div
          contentEditable
          suppressContentEditableWarning
          data-testid="test-contenteditable"
        >
          Test
        </div>
        <Header projectId="project-1" workflowId="workflow-1">
          {[<span key="breadcrumb-1">Breadcrumb</span>]}
        </Header>
      </>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext!();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    await waitFor(() => {
      expect(screen.getByTestId('save-workflow-button')).toBeInTheDocument();
    });

    const contentEditable = screen.getByTestId('test-contenteditable');
    await user.click(contentEditable);

    await user.keyboard('{Meta>}s{/Meta}');

    await waitFor(() => expect(saveWorkflowSpy).toHaveBeenCalled());

    unmount();
    cleanup();
  });
});

// =============================================================================
// SAVE & SYNC TO GITHUB KEYBOARD SHORTCUT TESTS (Cmd+Shift+S / Ctrl+Shift+S)
// =============================================================================

describe('Header - Save & Sync to GitHub (Cmd+Shift+S / Ctrl+Shift+S)', () => {
  beforeEach(() => {
    urlState.reset();
  });

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(async () => {
    // Wait for any pending async updates to settle after test
    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50));
    });
  });

  test('Cmd+Shift+S opens GitHub sync modal when conditions met (Mac)', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, openGitHubSyncModalSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        hasGithubConnection: true,
      });

    const { unmount } = await renderAndWaitForReady(
      wrapper,
      emitSessionContext!
    );

    await user.keyboard('{Meta>}{Shift>}s{/Shift}{/Meta}');

    await waitFor(() =>
      expect(openGitHubSyncModalSpy).toHaveBeenCalledTimes(1)
    );

    unmount();
    cleanup();
  });

  test('Ctrl+Shift+S opens GitHub sync modal when conditions met (Windows)', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, openGitHubSyncModalSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        hasGithubConnection: true,
      });

    const { unmount } = await renderAndWaitForReady(
      wrapper,
      emitSessionContext!
    );

    await user.keyboard('{Control>}{Shift>}s{/Shift}{/Control}');

    await waitFor(() =>
      expect(openGitHubSyncModalSpy).toHaveBeenCalledTimes(1)
    );

    unmount();
    cleanup();
  });

  test('Cmd+Shift+S does NOT open modal when no GitHub connection', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, openGitHubSyncModalSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        hasGithubConnection: false,
      });

    const { unmount } = await renderAndWaitForReady(
      wrapper,
      emitSessionContext!
    );

    await user.keyboard('{Meta>}{Shift>}s{/Shift}{/Meta}');

    // Wait to ensure handler doesn't fire
    await new Promise(resolve => setTimeout(resolve, 150));

    expect(openGitHubSyncModalSpy).not.toHaveBeenCalled();

    unmount();
    cleanup();
  });

  test('Cmd+Shift+S does NOT open modal when no edit permission', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, openGitHubSyncModalSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: false, can_run_workflow: true },
        hasGithubConnection: true,
      });

    const { unmount } = await renderAndWaitForReady(
      wrapper,
      emitSessionContext!
    );

    await user.keyboard('{Meta>}{Shift>}s{/Shift}{/Meta}');

    // Wait to ensure handler doesn't fire
    await new Promise(resolve => setTimeout(resolve, 150));

    expect(openGitHubSyncModalSpy).not.toHaveBeenCalled();

    unmount();
    cleanup();
  });

  test('Cmd+Shift+S does NOT open modal when workflow is deleted', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, openGitHubSyncModalSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        hasGithubConnection: true,
        workflowDeleted: true,
      });

    const { unmount } = await renderAndWaitForReady(
      wrapper,
      emitSessionContext!
    );

    await user.keyboard('{Meta>}{Shift>}s{/Shift}{/Meta}');

    // Wait to ensure handler doesn't fire
    await new Promise(resolve => setTimeout(resolve, 150));

    expect(openGitHubSyncModalSpy).not.toHaveBeenCalled();

    unmount();
    cleanup();
  });

  test('Cmd+Shift+S does NOT open modal when viewing pinned version', async () => {
    const user = userEvent.setup();

    // Set pinned version in URL
    urlState.setParam('v', '1');

    const { wrapper, emitSessionContext, openGitHubSyncModalSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        hasGithubConnection: true,
      });

    const { unmount } = await renderAndWaitForReady(
      wrapper,
      emitSessionContext!
    );

    await user.keyboard('{Meta>}{Shift>}s{/Shift}{/Meta}');

    // Wait to ensure handler doesn't fire
    await new Promise(resolve => setTimeout(resolve, 150));

    expect(openGitHubSyncModalSpy).not.toHaveBeenCalled();

    unmount();
    cleanup();
  });

  test('Cmd+Shift+S works in input fields (enableOnFormTags)', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, openGitHubSyncModalSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        hasGithubConnection: true,
      });

    const { unmount } = render(
      <>
        <input data-testid="test-input" />
        <Header projectId="project-1" workflowId="workflow-1">
          {[<span key="breadcrumb-1">Breadcrumb</span>]}
        </Header>
      </>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext!();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    await waitFor(() => {
      expect(screen.getByTestId('save-workflow-button')).toBeInTheDocument();
    });

    const input = screen.getByTestId('test-input');
    await user.click(input);

    await user.keyboard('{Meta>}{Shift>}s{/Shift}{/Meta}');

    await waitFor(() => expect(openGitHubSyncModalSpy).toHaveBeenCalled());

    unmount();
    cleanup();
  });

  test('Cmd+Shift+S works in textarea (enableOnFormTags)', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, openGitHubSyncModalSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        hasGithubConnection: true,
      });

    const { unmount } = render(
      <>
        <textarea data-testid="test-textarea" />
        <Header projectId="project-1" workflowId="workflow-1">
          {[<span key="breadcrumb-1">Breadcrumb</span>]}
        </Header>
      </>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext!();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    await waitFor(() => {
      expect(screen.getByTestId('save-workflow-button')).toBeInTheDocument();
    });

    const textarea = screen.getByTestId('test-textarea');
    await user.click(textarea);

    await user.keyboard('{Meta>}{Shift>}s{/Shift}{/Meta}');

    await waitFor(() => expect(openGitHubSyncModalSpy).toHaveBeenCalled());

    unmount();
    cleanup();
  });

  test('Cmd+Shift+S works in select (enableOnFormTags)', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, openGitHubSyncModalSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        hasGithubConnection: true,
      });

    const { unmount } = render(
      <>
        <select data-testid="test-select">
          <option value="1">Option 1</option>
        </select>
        <Header projectId="project-1" workflowId="workflow-1">
          {[<span key="breadcrumb-1">Breadcrumb</span>]}
        </Header>
      </>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext!();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    await waitFor(() => {
      expect(screen.getByTestId('save-workflow-button')).toBeInTheDocument();
    });

    const select = screen.getByTestId('test-select');
    await user.click(select);

    await user.keyboard('{Meta>}{Shift>}s{/Shift}{/Meta}');

    await waitFor(() => expect(openGitHubSyncModalSpy).toHaveBeenCalled());

    unmount();
    cleanup();
  });

  test('Cmd+Shift+S works in contentEditable (enableOnFormTags)', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, openGitHubSyncModalSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        hasGithubConnection: true,
      });

    const { unmount } = render(
      <>
        <div
          contentEditable
          suppressContentEditableWarning
          data-testid="test-contenteditable"
        >
          Test
        </div>
        <Header projectId="project-1" workflowId="workflow-1">
          {[<span key="breadcrumb-1">Breadcrumb</span>]}
        </Header>
      </>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext!();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    await waitFor(() => {
      expect(screen.getByTestId('save-workflow-button')).toBeInTheDocument();
    });

    const contentEditable = screen.getByTestId('test-contenteditable');
    await user.click(contentEditable);

    await user.keyboard('{Meta>}{Shift>}s{/Shift}{/Meta}');

    await waitFor(() => expect(openGitHubSyncModalSpy).toHaveBeenCalled());

    unmount();
    cleanup();
  });
});

// =============================================================================
// GUARD CONDITION INTERACTION TESTS
// =============================================================================

describe('Header - Guard Condition Interactions', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(async () => {
    // Wait for any pending async updates to settle after test
    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50));
    });
  });

  test('both guards respected when canSave=false', async () => {
    const user = userEvent.setup();
    const {
      wrapper,
      emitSessionContext,
      saveWorkflowSpy,
      openGitHubSyncModalSpy,
      cleanup,
    } = await createTestSetup({
      permissions: { can_edit_workflow: false, can_run_workflow: true },
      hasGithubConnection: true,
    });

    const { unmount } = await renderAndWaitForReady(
      wrapper,
      emitSessionContext!
    );

    // Try Cmd+S
    await user.keyboard('{Meta>}s{/Meta}');
    await new Promise(resolve => setTimeout(resolve, 150));
    expect(saveWorkflowSpy).not.toHaveBeenCalled();

    // Try Cmd+Shift+S
    await user.keyboard('{Meta>}{Shift>}s{/Shift}{/Meta}');
    await new Promise(resolve => setTimeout(resolve, 150));
    expect(openGitHubSyncModalSpy).not.toHaveBeenCalled();

    unmount();
    cleanup();
  });

  test('Cmd+S works but Cmd+Shift+S blocked when no GitHub connection', async () => {
    const user = userEvent.setup();
    const {
      wrapper,
      emitSessionContext,
      saveWorkflowSpy,
      openGitHubSyncModalSpy,
      cleanup,
    } = await createTestSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
      hasGithubConnection: false,
    });

    const { unmount } = await renderAndWaitForReady(
      wrapper,
      emitSessionContext!
    );

    // Cmd+S should work
    await user.keyboard('{Meta>}s{/Meta}');
    await waitFor(() => expect(saveWorkflowSpy).toHaveBeenCalledTimes(1));

    // Cmd+Shift+S should not work
    await user.keyboard('{Meta>}{Shift>}s{/Shift}{/Meta}');
    await new Promise(resolve => setTimeout(resolve, 150));
    expect(openGitHubSyncModalSpy).not.toHaveBeenCalled();

    unmount();
    cleanup();
  });

  test('both shortcuts work when all conditions met', async () => {
    const user = userEvent.setup();
    const {
      wrapper,
      emitSessionContext,
      saveWorkflowSpy,
      openGitHubSyncModalSpy,
      cleanup,
    } = await createTestSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
      hasGithubConnection: true,
    });

    const { unmount } = await renderAndWaitForReady(
      wrapper,
      emitSessionContext!
    );

    // Cmd+S should work
    await user.keyboard('{Meta>}s{/Meta}');
    await waitFor(() => expect(saveWorkflowSpy).toHaveBeenCalledTimes(1));

    // Cmd+Shift+S should work
    await user.keyboard('{Meta>}{Shift>}s{/Shift}{/Meta}');
    await waitFor(() =>
      expect(openGitHubSyncModalSpy).toHaveBeenCalledTimes(1)
    );

    unmount();
    cleanup();
  });
});

// =============================================================================
// SHARED RUN SETUP HELPER
// =============================================================================

/**
 * Sets up stores with a Y.Doc that already contains a trigger so that
 * `firstTriggerId` is defined and the shortcut guard passes.
 */
async function createRunSetup(
  options: WrapperOptions & {
    isRunPanelOpen?: boolean;
    isIDEOpen?: boolean;
  } = {}
) {
  const {
    isRunPanelOpen = false,
    isIDEOpen = false,
    ...wrapperOptions
  } = options;

  const ydoc = createWorkflowYDocWithTrigger(
    wrapperOptions.workflowLockVersion ?? 1
  );

  const { stores, sessionStore, cleanup, emitSessionContext } =
    await simulateStoreProviderWithConnection(
      'test:room',
      { id: 'user-1', name: 'Test User', color: '#ff0000' },
      {
        workflowYDoc: ydoc,
        sessionContext: {
          permissions: wrapperOptions.permissions ?? {
            can_edit_workflow: true,
            can_run_workflow: true,
          },
          latest_snapshot_lock_version:
            wrapperOptions.latestSnapshotLockVersion ?? 1,
        },
        emitSessionContext: true,
      }
    );

  // Manually emit sync so isSynced becomes true
  const provider = sessionStore.getProvider();
  if (provider) {
    (provider as any).emit('sync', [true]);
  }
  await new Promise(resolve => setTimeout(resolve, 150));

  vi.spyOn(stores.workflowStore, 'saveWorkflow').mockResolvedValue(null);

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <KeyboardProvider>
      <SessionContext.Provider value={{ sessionStore, isNewWorkflow: false }}>
        <StoreContext.Provider value={stores}>{children}</StoreContext.Provider>
      </SessionContext.Provider>
    </KeyboardProvider>
  );

  async function renderAndWait() {
    const result = render(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        isRunPanelOpen={isRunPanelOpen}
        isIDEOpen={isIDEOpen}
      >
        {[<span key="b">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext!();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    await waitFor(() => {
      expect(screen.getByTestId('save-workflow-button')).toBeInTheDocument();
    });

    return result;
  }

  return { wrapper, stores, emitSessionContext, cleanup, renderAndWait };
}

// =============================================================================
// CMD+ENTER / CTRL+ENTER – SUBMIT MANUAL RUN
// =============================================================================

describe('Header - Submit Manual Run (Cmd+Enter / Ctrl+Enter)', () => {
  beforeEach(() => {
    urlState.reset();
    vi.clearAllMocks();
    // Default: submitManualRun resolves successfully
    mockSubmitManualRun.mockResolvedValue({ data: { run_id: 'run-123' } });
  });

  afterEach(async () => {
    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50));
    });
  });

  test('Cmd+Enter submits run when canRun is true (Mac)', async () => {
    const user = userEvent.setup();
    const { renderAndWait, cleanup } = await createRunSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
    });

    const { unmount } = await renderAndWait();

    await user.keyboard('{Meta>}{Enter}{/Meta}');

    await waitFor(() => expect(mockSubmitManualRun).toHaveBeenCalledTimes(1));
    expect(mockSubmitManualRun).toHaveBeenCalledWith(
      expect.objectContaining({
        workflowId: 'workflow-1',
        projectId: 'project-1',
        triggerId: 'trigger-test-1',
      })
    );

    unmount();
    cleanup();
  });

  test('Ctrl+Enter submits run when canRun is true (Windows)', async () => {
    const user = userEvent.setup();
    const { renderAndWait, cleanup } = await createRunSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
    });

    const { unmount } = await renderAndWait();

    await user.keyboard('{Control>}{Enter}{/Control}');

    await waitFor(() => expect(mockSubmitManualRun).toHaveBeenCalledTimes(1));

    unmount();
    cleanup();
  });

  test('Cmd+Enter does NOT submit run when no run permission', async () => {
    const user = userEvent.setup();
    // canRun requires hasEditPermission OR hasRunPermission — both must be false
    const { renderAndWait, cleanup } = await createRunSetup({
      permissions: { can_edit_workflow: false, can_run_workflow: false },
    });

    const { unmount } = await renderAndWait();

    await user.keyboard('{Meta>}{Enter}{/Meta}');

    await new Promise(resolve => setTimeout(resolve, 150));
    expect(mockSubmitManualRun).not.toHaveBeenCalled();

    unmount();
    cleanup();
  });

  test('Cmd+Enter does NOT submit run when run panel is open', async () => {
    const user = userEvent.setup();
    const { renderAndWait, cleanup } = await createRunSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
      isRunPanelOpen: true,
    });

    const { unmount } = await renderAndWait();

    await user.keyboard('{Meta>}{Enter}{/Meta}');

    await new Promise(resolve => setTimeout(resolve, 150));
    expect(mockSubmitManualRun).not.toHaveBeenCalled();

    unmount();
    cleanup();
  });

  test('Cmd+Enter does NOT submit run when IDE is open', async () => {
    const user = userEvent.setup();
    const { renderAndWait, cleanup } = await createRunSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
      isIDEOpen: true,
    });

    const { unmount } = await renderAndWait();

    await user.keyboard('{Meta>}{Enter}{/Meta}');

    await new Promise(resolve => setTimeout(resolve, 150));
    expect(mockSubmitManualRun).not.toHaveBeenCalled();

    unmount();
    cleanup();
  });
});

// =============================================================================
// CMD+SHIFT+ENTER – RUN WITH CUSTOM INPUT (no run loaded)
// =============================================================================

describe('Header - Cmd+Shift+Enter (Run with custom input)', () => {
  beforeEach(() => {
    urlState.reset();
    vi.clearAllMocks();
    mockSubmitManualRun.mockResolvedValue({ data: { run_id: 'run-123' } });
  });

  afterEach(async () => {
    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50));
    });
  });

  test('Cmd+Shift+Enter navigates to run panel with custom input when no run is loaded (Mac)', async () => {
    const user = userEvent.setup();
    const { renderAndWait, cleanup } = await createRunSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
    });

    const { unmount } = await renderAndWait();

    await user.keyboard('{Meta>}{Shift>}{Enter}{/Shift}{/Meta}');

    await waitFor(() =>
      expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith(
        expect.objectContaining({ panel: 'run' })
      )
    );
    expect(mockSubmitManualRun).not.toHaveBeenCalled();

    unmount();
    cleanup();
  });

  test('Ctrl+Shift+Enter navigates to run panel with custom input when no run is loaded (Windows)', async () => {
    const user = userEvent.setup();
    const { renderAndWait, cleanup } = await createRunSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
    });

    const { unmount } = await renderAndWait();

    await user.keyboard('{Control>}{Shift>}{Enter}{/Shift}{/Control}');

    await waitFor(() =>
      expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith(
        expect.objectContaining({ panel: 'run' })
      )
    );

    unmount();
    cleanup();
  });

  test('Cmd+Shift+Enter does NOT navigate to run panel when run panel is already open', async () => {
    const user = userEvent.setup();
    const { renderAndWait, cleanup } = await createRunSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
      isRunPanelOpen: true,
    });

    const { unmount } = await renderAndWait();

    await user.keyboard('{Meta>}{Shift>}{Enter}{/Shift}{/Meta}');

    await new Promise(resolve => setTimeout(resolve, 150));
    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalledWith(
      expect.objectContaining({ panel: 'run' })
    );

    unmount();
    cleanup();
  });
});

// =============================================================================
// CMD+ENTER / CMD+SHIFT+ENTER – RETRY & NEW WORK ORDER (run loaded)
// =============================================================================

const FOLLOWED_RUN_ID = '11111111-1111-1111-1111-111111111111';
const STEP_ID = '22222222-2222-2222-2222-222222222222';

const mockRetryableRun: RunDetail = {
  id: FOLLOWED_RUN_ID,
  work_order_id: '33333333-3333-3333-3333-333333333333',
  work_order: {
    id: '33333333-3333-3333-3333-333333333333',
    workflow_id: 'workflow-1',
  },
  state: 'success',
  created_by: null,
  starting_trigger: null,
  started_at: '2024-01-01T00:00:00Z',
  finished_at: '2024-01-01T00:01:00Z',
  inserted_at: '2024-01-01T00:00:00Z',
  steps: [
    {
      id: STEP_ID,
      job_id: '44444444-4444-4444-4444-444444444444',
      job: { name: 'Test Job' },
      exit_reason: 'normal',
      error_type: null,
      started_at: '2024-01-01T00:00:00Z',
      finished_at: '2024-01-01T00:01:00Z',
      input_dataclip_id: null,
      output_dataclip_id: null,
      inserted_at: '2024-01-01T00:00:00Z',
    },
  ],
};

describe('Header - Retry shortcuts (run loaded)', () => {
  let mockFetch: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    urlState.reset();
    vi.clearAllMocks();
    mockSubmitManualRun.mockResolvedValue({ data: { run_id: 'run-new-456' } });

    mockFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ data: { run_id: 'run-retried-789' } }),
    });
    vi.stubGlobal('fetch', mockFetch);
  });

  afterEach(async () => {
    vi.unstubAllGlobals();
    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 50));
    });
  });

  async function createRetrySetup() {
    urlState.setParam('run', FOLLOWED_RUN_ID);

    const setup = await createRunSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
    });

    act(() => {
      setup.stores.historyStore._setActiveRunForTesting(mockRetryableRun);
    });

    return setup;
  }

  test('Cmd+Enter retries the loaded run instead of creating a new work order (Mac)', async () => {
    const user = userEvent.setup();
    const { renderAndWait, cleanup } = await createRetrySetup();

    const { unmount } = await renderAndWait();

    await user.keyboard('{Meta>}{Enter}{/Meta}');

    await waitFor(() =>
      expect(mockFetch).toHaveBeenCalledWith(
        expect.stringContaining(`/runs/${FOLLOWED_RUN_ID}/retry`),
        expect.objectContaining({ method: 'POST' })
      )
    );
    expect(mockSubmitManualRun).not.toHaveBeenCalled();

    unmount();
    cleanup();
  });

  test('Ctrl+Enter retries the loaded run instead of creating a new work order (Windows)', async () => {
    const user = userEvent.setup();
    const { renderAndWait, cleanup } = await createRetrySetup();

    const { unmount } = await renderAndWait();

    await user.keyboard('{Control>}{Enter}{/Control}');

    await waitFor(() =>
      expect(mockFetch).toHaveBeenCalledWith(
        expect.stringContaining(`/runs/${FOLLOWED_RUN_ID}/retry`),
        expect.objectContaining({ method: 'POST' })
      )
    );
    expect(mockSubmitManualRun).not.toHaveBeenCalled();

    unmount();
    cleanup();
  });

  test('Cmd+Shift+Enter navigates to run panel with custom input even when run is loaded (Mac)', async () => {
    const user = userEvent.setup();
    const { renderAndWait, cleanup } = await createRetrySetup();

    const { unmount } = await renderAndWait();

    await user.keyboard('{Meta>}{Shift>}{Enter}{/Shift}{/Meta}');

    await waitFor(() =>
      expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith(
        expect.objectContaining({ panel: 'run' })
      )
    );
    expect(mockFetch).not.toHaveBeenCalledWith(
      expect.stringContaining('/retry'),
      expect.anything()
    );

    unmount();
    cleanup();
  });
});
