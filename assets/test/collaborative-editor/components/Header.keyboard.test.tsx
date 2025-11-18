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

import { Header } from '../../../js/collaborative-editor/components/Header';
import { SessionContext } from '../../../js/collaborative-editor/contexts/SessionProvider';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { KeyboardProvider } from '../../../js/collaborative-editor/keyboard';
import type { CreateSessionContextOptions } from '../__helpers__/sessionContextFactory';
import { simulateStoreProviderWithConnection } from '../__helpers__/storeProviderHelpers';
import { createMinimalWorkflowYDoc } from '../__helpers__/workflowStoreHelpers';

// =============================================================================
// TEST MOCKS
// =============================================================================

// Mock useAdaptorIcons to prevent async fetch warnings
vi.mock('../../../js/workflow-diagram/useAdaptorIcons', () => ({
  default: () => ({}),
}));

// Mock Tooltip to prevent Radix UI timer-based updates
vi.mock('../../../js/collaborative-editor/components/Tooltip', () => ({
  Tooltip: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

// =============================================================================
// TEST HELPERS
// =============================================================================

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

  test('Cmd+S does NOT call saveWorkflow when viewing old snapshot', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, saveWorkflowSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        workflowLockVersion: 1,
        latestSnapshotLockVersion: 2,
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

  test('Cmd+Shift+S does NOT open modal when viewing old snapshot', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, openGitHubSyncModalSpy, cleanup } =
      await createTestSetup({
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        hasGithubConnection: true,
        workflowLockVersion: 1,
        latestSnapshotLockVersion: 2,
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
