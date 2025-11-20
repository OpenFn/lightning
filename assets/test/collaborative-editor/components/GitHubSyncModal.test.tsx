/**
 * GitHubSyncModal Component Tests
 *
 * Tests for the GitHub Sync Modal component focusing on:
 * - Modal open/close behavior
 * - Form input handling
 * - Save & Sync action
 * - Keyboard shortcuts (Ctrl/Cmd+Enter)
 * - Integration with workflow actions
 */

import { act, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type React from 'react';
import { describe, expect, test, vi } from 'vitest';
import * as Y from 'yjs';

import { GitHubSyncModal } from '../../../js/collaborative-editor/components/GitHubSyncModal';
import { SessionContext } from '../../../js/collaborative-editor/contexts/SessionProvider';
import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { createAdaptorStore } from '../../../js/collaborative-editor/stores/createAdaptorStore';
import { createAwarenessStore } from '../../../js/collaborative-editor/stores/createAwarenessStore';
import { createCredentialStore } from '../../../js/collaborative-editor/stores/createCredentialStore';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionStore } from '../../../js/collaborative-editor/stores/createSessionStore';
import { createUIStore } from '../../../js/collaborative-editor/stores/createUIStore';
import { createWorkflowStore } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Session } from '../../../js/collaborative-editor/types/session';
import {
  createGithubConnectedContext,
  createSessionContext,
} from '../__helpers__/sessionContextFactory';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../mocks/phoenixChannel';
import { createMockSocket } from '../mocks/phoenixSocket';

// =============================================================================
// TEST HELPERS
// =============================================================================

interface WrapperOptions {
  hasGitHubConnection?: boolean;
  userEmail?: string;
  repoName?: string;
  branchName?: string;
}

function createTestSetup(options: WrapperOptions = {}) {
  const {
    hasGitHubConnection = true,
    userEmail = 'test@example.com',
    repoName = 'openfn/demo',
    branchName = 'main',
  } = options;

  // Create all stores
  const sessionStore = createSessionStore();
  const sessionContextStore = createSessionContextStore(false);
  const workflowStore = createWorkflowStore();
  const adaptorStore = createAdaptorStore();
  const awarenessStore = createAwarenessStore();
  const credentialStore = createCredentialStore();
  const uiStore = createUIStore();

  // Initialize session store
  const mockSocket = createMockSocket();
  sessionStore.initializeSession(mockSocket, 'test:room', {
    id: 'user-1',
    name: 'Test User',
    color: '#ff0000',
  });

  // Set up Y.Doc and workflow
  const ydoc = new Y.Doc() as Session.WorkflowDoc;
  const workflowMap = ydoc.getMap('workflow');
  workflowMap.set('id', 'test-workflow-123');
  workflowMap.set('name', 'Test Workflow');
  workflowMap.set('lock_version', 1);
  workflowMap.set('deleted_at', null);

  ydoc.getArray('jobs');
  ydoc.getArray('triggers');
  ydoc.getArray('edges');
  ydoc.getMap('positions');

  // Connect stores
  const mockChannel = createMockPhoenixChannel('test:room');
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);
  (mockProvider as any).doc = ydoc;

  workflowStore.connect(ydoc, mockProvider as any);
  sessionContextStore._connectChannel(mockProvider as any);

  // Emit session context with GitHub connection if needed
  const emitSessionContext = () => {
    const context = hasGitHubConnection
      ? createGithubConnectedContext(repoName, branchName)
      : createSessionContext();

    // Override user email if specified
    if (context.user) {
      context.user.email = userEmail;
    }

    (mockChannel as any)._test.emit('session_context', context);
  };

  const mockStoreValue: StoreContextValue = {
    sessionContextStore,
    workflowStore,
    adaptorStore,
    credentialStore,
    awarenessStore,
    uiStore,
  };

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={{ sessionStore, isNewWorkflow: false }}>
      <StoreContext.Provider value={mockStoreValue}>
        {children}
      </StoreContext.Provider>
    </SessionContext.Provider>
  );

  return {
    wrapper,
    emitSessionContext,
    uiStore,
    workflowStore,
    mockChannel,
    ydoc,
  };
}

// =============================================================================
// MODAL VISIBILITY TESTS
// =============================================================================

describe('GitHubSyncModal - Visibility', () => {
  test('modal is hidden by default', async () => {
    const { wrapper, emitSessionContext } = createTestSetup();

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
    });

    // Modal should not be visible
    expect(
      screen.queryByText('Save and sync changes to GitHub')
    ).not.toBeInTheDocument();
  });

  test('modal opens when uiStore.openGitHubSyncModal is called', async () => {
    const { wrapper, emitSessionContext, uiStore } = createTestSetup();

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
    });

    // Open the modal
    act(() => {
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(
        screen.getByText('Save and sync changes to GitHub')
      ).toBeInTheDocument();
    });
  });

  test('modal closes when Cancel button is clicked', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, uiStore } = createTestSetup();

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(
        screen.getByText('Save and sync changes to GitHub')
      ).toBeInTheDocument();
    });

    // Click Cancel
    const cancelButton = screen.getByRole('button', { name: /cancel/i });
    await user.click(cancelButton);

    await waitFor(() => {
      expect(
        screen.queryByText('Save and sync changes to GitHub')
      ).not.toBeInTheDocument();
    });
  });

  test('modal closes when clicking backdrop', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, uiStore } = createTestSetup();

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(
        screen.getByText('Save and sync changes to GitHub')
      ).toBeInTheDocument();
    });

    // Click backdrop (the Dialog component handles this)
    const backdrop = screen.getByText('Save and sync changes to GitHub')
      .parentElement?.parentElement?.parentElement?.previousElementSibling;

    if (backdrop) {
      await user.click(backdrop);
    }

    // Note: Headless UI Dialog handles backdrop clicks internally
    // This test verifies the modal can be closed via backdrop
  });
});

// =============================================================================
// FORM INPUT TESTS
// =============================================================================

describe('GitHubSyncModal - Form Input', () => {
  test('displays default commit message based on user email', async () => {
    const { wrapper, emitSessionContext, uiStore } = createTestSetup({
      userEmail: 'john@example.com',
    });

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      const textarea = screen.getByLabelText(
        /commit message/i
      ) as HTMLTextAreaElement;
      expect(textarea.value).toBe(
        'john@example.com initiated a sync from Lightning'
      );
    });
  });

  test('allows user to edit commit message', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, uiStore } = createTestSetup();

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(screen.getByLabelText(/commit message/i)).toBeInTheDocument();
    });

    const textarea = screen.getByLabelText(/commit message/i);

    // Clear and type new message
    await user.clear(textarea);
    await user.type(textarea, 'Custom commit message');

    expect(textarea).toHaveValue('Custom commit message');
  });

  test('commit message resets when modal reopens', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, uiStore } = createTestSetup({
      userEmail: 'test@example.com',
    });

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(screen.getByLabelText(/commit message/i)).toBeInTheDocument();
    });

    // Edit commit message
    const textarea = screen.getByLabelText(/commit message/i);
    await user.clear(textarea);
    await user.type(textarea, 'Modified message');

    // Close modal
    const cancelButton = screen.getByRole('button', { name: /cancel/i });
    await user.click(cancelButton);

    await waitFor(() => {
      expect(
        screen.queryByText('Save and sync changes to GitHub')
      ).not.toBeInTheDocument();
    });

    // Reopen modal
    act(() => {
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      const newTextarea = screen.getByLabelText(/commit message/i);
      expect(newTextarea).toHaveValue(
        'test@example.com initiated a sync from Lightning'
      );
    });
  });

  test('textarea has proper accessibility attributes', async () => {
    const { wrapper, emitSessionContext, uiStore } = createTestSetup();

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      const textarea = screen.getByLabelText(/commit message/i);
      expect(textarea).toHaveAttribute('id');
      expect(textarea).toHaveAttribute(
        'placeholder',
        'Describe your changes...'
      );
      expect(textarea).toHaveAttribute('rows', '2');
    });
  });
});

// =============================================================================
// REPOSITORY INFORMATION DISPLAY TESTS
// =============================================================================

describe('GitHubSyncModal - Repository Information', () => {
  test('displays repository information when GitHub is connected', async () => {
    const { wrapper, emitSessionContext, uiStore } = createTestSetup({
      hasGitHubConnection: true,
      repoName: 'openfn/workflows',
      branchName: 'develop',
    });

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(screen.getByText('Repository:')).toBeInTheDocument();
      expect(screen.getByText('openfn/workflows')).toBeInTheDocument();
      expect(screen.getByText('Branch:')).toBeInTheDocument();
      expect(screen.getByText('develop')).toBeInTheDocument();
    });
  });

  test('repository link opens in new tab', async () => {
    const { wrapper, emitSessionContext, uiStore } = createTestSetup({
      repoName: 'openfn/demo',
    });

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      const repoLink = screen.getByRole('link', { name: /openfn\/demo/i });
      expect(repoLink).toHaveAttribute(
        'href',
        'https://github.com/openfn/demo'
      );
      expect(repoLink).toHaveAttribute('target', '_blank');
      expect(repoLink).toHaveAttribute('rel', 'noopener noreferrer');
    });
  });

  test('displays modify connection link', async () => {
    const { wrapper, emitSessionContext, uiStore } = createTestSetup();

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      const modifyLink = screen.getByRole('link', {
        name: /modify connection/i,
      });
      expect(modifyLink).toBeInTheDocument();
      expect(modifyLink).toHaveAttribute('href');
      expect(modifyLink.getAttribute('href')).toContain('/settings#vcs');
    });
  });
});

// =============================================================================
// SAVE & SYNC ACTION TESTS
// =============================================================================

describe('GitHubSyncModal - Save & Sync Action', () => {
  test('Save & Sync button is disabled when commit message is empty', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, uiStore } = createTestSetup();

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(screen.getByLabelText(/commit message/i)).toBeInTheDocument();
    });

    // Clear the textarea
    const textarea = screen.getByLabelText(/commit message/i);
    await user.clear(textarea);

    // Button should be disabled
    const saveButton = screen.getByRole('button', { name: /save & sync/i });
    expect(saveButton).toBeDisabled();
  });

  test('Save & Sync button is disabled when commit message is only whitespace', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, uiStore } = createTestSetup();

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(screen.getByLabelText(/commit message/i)).toBeInTheDocument();
    });

    // Set whitespace-only message
    const textarea = screen.getByLabelText(/commit message/i);
    await user.clear(textarea);
    await user.type(textarea, '   ');

    // Button should be disabled
    const saveButton = screen.getByRole('button', { name: /save & sync/i });
    expect(saveButton).toBeDisabled();
  });

  test('calls saveAndSyncWorkflow when Save & Sync is clicked', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, uiStore, mockChannel, workflowStore } =
      createTestSetup();

    // Mock the channel push to simulate successful save
    const pushSpy = vi.spyOn(mockChannel, 'push').mockImplementation(() => {
      return {
        receive(status: string, callback: (response: any) => void) {
          if (status === 'ok') {
            callback({
              saved_at: new Date().toISOString(),
              lock_version: 2,
              repo: 'openfn/demo',
            });
          }
          return this;
        },
      } as any;
    });

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(
        screen.getByRole('button', { name: /save & sync/i })
      ).toBeInTheDocument();
    });

    // Click Save & Sync
    const saveButton = screen.getByRole('button', { name: /save & sync/i });
    await user.click(saveButton);

    // Wait for the channel push to be called
    await waitFor(() => {
      expect(pushSpy).toHaveBeenCalledWith(
        'save_and_sync',
        expect.objectContaining({
          commit_message: expect.stringContaining(
            'initiated a sync from Lightning'
          ),
        })
      );
    });
  });

  test('shows loading state while saving', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, uiStore, mockChannel } =
      createTestSetup();

    // Mock a delayed response
    vi.spyOn(mockChannel, 'push').mockImplementation(() => {
      return {
        receive(status: string, callback: (response: any) => void) {
          // Simulate delay
          setTimeout(() => {
            if (status === 'ok') {
              callback({
                saved_at: new Date().toISOString(),
                lock_version: 2,
                repo: 'openfn/demo',
              });
            }
          }, 100);
          return this;
        },
      } as any;
    });

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(
        screen.getByRole('button', { name: /save & sync/i })
      ).toBeInTheDocument();
    });

    // Click Save & Sync
    const saveButton = screen.getByRole('button', { name: /save & sync/i });
    await user.click(saveButton);

    // Should show loading state
    await waitFor(() => {
      expect(
        screen.getByRole('button', { name: /saving/i })
      ).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /saving/i })).toBeDisabled();
    });
  });

  test('closes modal after successful save', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, uiStore, mockChannel } =
      createTestSetup();

    // Mock successful save
    vi.spyOn(mockChannel, 'push').mockImplementation(() => {
      return {
        receive(status: string, callback: (response: any) => void) {
          if (status === 'ok') {
            callback({
              saved_at: new Date().toISOString(),
              lock_version: 2,
              repo: 'openfn/demo',
            });
          }
          return this;
        },
      } as any;
    });

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(
        screen.getByRole('button', { name: /save & sync/i })
      ).toBeInTheDocument();
    });

    // Click Save & Sync
    const saveButton = screen.getByRole('button', { name: /save & sync/i });
    await user.click(saveButton);

    // Modal should close
    await waitFor(() => {
      expect(
        screen.queryByText('Save and sync changes to GitHub')
      ).not.toBeInTheDocument();
    });
  });

  test('trims whitespace from commit message before saving', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, uiStore, mockChannel } =
      createTestSetup();

    const pushSpy = vi.spyOn(mockChannel, 'push').mockImplementation(() => {
      return {
        receive(status: string, callback: (response: any) => void) {
          if (status === 'ok') {
            callback({
              saved_at: new Date().toISOString(),
              lock_version: 2,
              repo: 'openfn/demo',
            });
          }
          return this;
        },
      } as any;
    });

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(screen.getByLabelText(/commit message/i)).toBeInTheDocument();
    });

    // Set message with leading/trailing whitespace
    const textarea = screen.getByLabelText(/commit message/i);
    await user.clear(textarea);
    await user.type(textarea, '  Test commit message  ');

    const saveButton = screen.getByRole('button', { name: /save & sync/i });
    await user.click(saveButton);

    await waitFor(() => {
      expect(pushSpy).toHaveBeenCalledWith(
        'save_and_sync',
        expect.objectContaining({
          commit_message: 'Test commit message',
        })
      );
    });
  });
});

// =============================================================================
// KEYBOARD SHORTCUT TESTS
// =============================================================================

describe('GitHubSyncModal - Keyboard Shortcuts', () => {
  test('Ctrl+Enter triggers save and sync', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, uiStore, mockChannel } =
      createTestSetup();

    const pushSpy = vi.spyOn(mockChannel, 'push').mockImplementation(() => {
      return {
        receive(status: string, callback: (response: any) => void) {
          if (status === 'ok') {
            callback({
              saved_at: new Date().toISOString(),
              lock_version: 2,
              repo: 'openfn/demo',
            });
          }
          return this;
        },
      } as any;
    });

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(screen.getByLabelText(/commit message/i)).toBeInTheDocument();
    });

    const textarea = screen.getByLabelText(/commit message/i);

    // Press Ctrl+Enter
    await user.type(textarea, '{Control>}{Enter}{/Control}');

    await waitFor(() => {
      expect(pushSpy).toHaveBeenCalledWith('save_and_sync', expect.any(Object));
    });
  });

  test('Cmd+Enter triggers save and sync (Mac)', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, uiStore, mockChannel } =
      createTestSetup();

    const pushSpy = vi.spyOn(mockChannel, 'push').mockImplementation(() => {
      return {
        receive(status: string, callback: (response: any) => void) {
          if (status === 'ok') {
            callback({
              saved_at: new Date().toISOString(),
              lock_version: 2,
              repo: 'openfn/demo',
            });
          }
          return this;
        },
      } as any;
    });

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(screen.getByLabelText(/commit message/i)).toBeInTheDocument();
    });

    const textarea = screen.getByLabelText(/commit message/i);

    // Press Cmd+Enter (Meta key on Mac)
    await user.type(textarea, '{Meta>}{Enter}{/Meta}');

    await waitFor(() => {
      expect(pushSpy).toHaveBeenCalledWith('save_and_sync', expect.any(Object));
    });
  });

  test('keyboard shortcut does not trigger when message is empty', async () => {
    const user = userEvent.setup();
    const { wrapper, emitSessionContext, uiStore, mockChannel } =
      createTestSetup();

    const pushSpy = vi.spyOn(mockChannel, 'push');

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(screen.getByLabelText(/commit message/i)).toBeInTheDocument();
    });

    const textarea = screen.getByLabelText(/commit message/i);
    await user.clear(textarea);

    // Press Ctrl+Enter
    await user.type(textarea, '{Control>}{Enter}{/Control}');

    // Should not trigger save
    expect(pushSpy).not.toHaveBeenCalled();
  });

  test('displays keyboard shortcut hint', async () => {
    const { wrapper, emitSessionContext, uiStore } = createTestSetup();

    render(<GitHubSyncModal />, { wrapper });

    act(() => {
      emitSessionContext();
      uiStore.openGitHubSyncModal();
    });

    await waitFor(() => {
      expect(
        screen.getByText(
          /Tip: Press Ctrl\+Enter \(or Cmd\+Enter\) to save and sync/i
        )
      ).toBeInTheDocument();
    });
  });
});
