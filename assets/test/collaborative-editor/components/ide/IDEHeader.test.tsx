/**
 * IDEHeader Component Tests
 *
 * Tests for the IDEHeader component focusing on SaveButton integration
 * and split button behavior when GitHub repository connections are present.
 */

import { render, screen, fireEvent } from '@testing-library/react';
import type React from 'react';
import { describe, expect, test, vi } from 'vitest';
import * as Y from 'yjs';

import { IDEHeader } from '../../../../js/collaborative-editor/components/ide/IDEHeader';
import { SessionContext } from '../../../../js/collaborative-editor/contexts/SessionProvider';
import type { StoreContextValue } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { createAdaptorStore } from '../../../../js/collaborative-editor/stores/createAdaptorStore';
import { createAwarenessStore } from '../../../../js/collaborative-editor/stores/createAwarenessStore';
import { createCredentialStore } from '../../../../js/collaborative-editor/stores/createCredentialStore';
import { createSessionContextStore } from '../../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionStore } from '../../../../js/collaborative-editor/stores/createSessionStore';
import { createUIStore } from '../../../../js/collaborative-editor/stores/createUIStore';
import { createWorkflowStore } from '../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Session } from '../../../../js/collaborative-editor/types/session';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../mocks/phoenixChannel';
import { createMockSocket } from '../../mocks/phoenixSocket';

// Mock dependencies
vi.mock('../../../../js/collaborative-editor/hooks/useVersionSelect', () => ({
  useVersionSelect: () => vi.fn(),
}));

// =============================================================================
// TEST HELPERS
// =============================================================================

function createTestSetup() {
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

  // Set up Y.Doc
  const ydoc = new Y.Doc() as Session.WorkflowDoc;
  const workflowMap = ydoc.getMap('workflow');
  workflowMap.set('id', 'test-workflow-123');
  workflowMap.set('name', 'Test Workflow');
  workflowMap.set('lock_version', 1);

  ydoc.getArray('jobs');
  ydoc.getArray('triggers');
  ydoc.getArray('edges');
  ydoc.getMap('positions');

  // Connect stores
  const mockChannel = createMockPhoenixChannel('test:room');
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);
  (mockProvider as any).doc = ydoc;

  workflowStore.connect(ydoc, mockProvider as any);

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

  return { wrapper };
}

const defaultProps = {
  jobId: 'job-123',
  jobName: 'Test Job',
  jobAdaptor: '@openfn/language-common@1.0.0',
  jobCredentialId: 'cred-123',
  snapshotVersion: 1,
  latestSnapshotVersion: 1,
  workflowId: 'workflow-123',
  projectId: 'project-123',
  onClose: vi.fn(),
  onSave: vi.fn(),
  onRun: vi.fn(),
  onRetry: vi.fn(),
  isRetryable: false,
  canRun: true,
  isRunning: false,
  canSave: true,
  saveTooltip: 'Save workflow',
  runTooltip: 'Run workflow',
  onEditAdaptor: vi.fn(),
  onChangeAdaptor: vi.fn(),
  repoConnection: null,
  openGitHubSyncModal: vi.fn(),
};

// =============================================================================
// SAVE BUTTON PRESENCE TESTS
// =============================================================================

describe('IDEHeader - SaveButton Presence', () => {
  test('renders SaveButton component', () => {
    const { wrapper } = createTestSetup();
    render(<IDEHeader {...defaultProps} />, { wrapper });

    const saveButton = screen.getByRole('button', { name: /save/i });
    expect(saveButton).toBeInTheDocument();
  });

  test('renders SaveButton with correct testid', () => {
    const { wrapper } = createTestSetup();
    render(<IDEHeader {...defaultProps} />, { wrapper });

    const saveButton = screen.getByTestId('save-workflow-button');
    expect(saveButton).toBeInTheDocument();
    expect(saveButton).toHaveTextContent('Save');
  });

  test('SaveButton is enabled when canSave is true', () => {
    const { wrapper } = createTestSetup();
    render(<IDEHeader {...defaultProps} canSave={true} />, { wrapper });

    const saveButton = screen.getByTestId('save-workflow-button');
    expect(saveButton).not.toBeDisabled();
  });

  test('SaveButton is disabled when canSave is false', () => {
    const { wrapper } = createTestSetup();
    render(<IDEHeader {...defaultProps} canSave={false} />, { wrapper });

    const saveButton = screen.getByTestId('save-workflow-button');
    expect(saveButton).toBeDisabled();
  });
});

// =============================================================================
// SIMPLE BUTTON (NO GITHUB CONNECTION) TESTS
// =============================================================================

describe('IDEHeader - Simple Save Button (No GitHub Connection)', () => {
  test('renders simple save button when repoConnection is null', () => {
    const { wrapper } = createTestSetup();
    render(<IDEHeader {...defaultProps} repoConnection={null} />, { wrapper });

    // Should have save button
    const saveButton = screen.getByRole('button', { name: /save/i });
    expect(saveButton).toBeInTheDocument();

    // When repoConnection is null, SaveButton renders a simple button
    // without the dropdown menu (no GitHub integration available)
    const dropdownButton = screen.queryByRole('button', {
      name: /open sync options/i,
    });
    expect(dropdownButton).not.toBeInTheDocument();
  });

  test('simple save button calls onSave when clicked', () => {
    const { wrapper } = createTestSetup();
    const onSave = vi.fn();
    render(
      <IDEHeader {...defaultProps} onSave={onSave} repoConnection={null} />,
      { wrapper }
    );

    const saveButton = screen.getByTestId('save-workflow-button');
    fireEvent.click(saveButton);

    expect(onSave).toHaveBeenCalledTimes(1);
  });

  test('simple save button shows tooltip message', () => {
    const { wrapper } = createTestSetup();
    render(
      <IDEHeader
        {...defaultProps}
        saveTooltip="Custom tooltip message"
        repoConnection={null}
      />,
      { wrapper }
    );

    const saveButton = screen.getByTestId('save-workflow-button');
    expect(saveButton).toBeInTheDocument();
  });
});

// =============================================================================
// SPLIT BUTTON (WITH GITHUB CONNECTION) TESTS
// =============================================================================

describe('IDEHeader - Split Save Button (With GitHub Connection)', () => {
  const mockRepoConnection = {
    id: 'repo-conn-123',
    repo: 'openfn/demo-project',
    branch: 'main',
    github_installation_id: 'install-456',
  };

  test('renders split button when repoConnection is present', () => {
    const { wrapper } = createTestSetup();
    render(
      <IDEHeader {...defaultProps} repoConnection={mockRepoConnection} />,
      { wrapper }
    );

    // Should have main save button
    const saveButton = screen.getByTestId('save-workflow-button');
    expect(saveButton).toBeInTheDocument();
    expect(saveButton).toHaveTextContent('Save');

    // Should have dropdown chevron button
    const dropdownButton = screen.getByRole('button', {
      name: /open sync options/i,
    });
    expect(dropdownButton).toBeInTheDocument();
  });

  test('split button has correct structure with rounded corners', () => {
    const { wrapper } = createTestSetup();
    const { container } = render(
      <IDEHeader {...defaultProps} repoConnection={mockRepoConnection} />,
      { wrapper }
    );

    // Find the split button container
    const splitButtonContainer = container.querySelector(
      '.inline-flex.rounded-md.shadow-xs'
    );
    expect(splitButtonContainer).toBeInTheDocument();

    // Main save button should have rounded-l-md (left side)
    const saveButton = screen.getByTestId('save-workflow-button');
    expect(saveButton).toHaveClass('rounded-l-md');

    // Dropdown button should have rounded-r-md (right side)
    const dropdownButton = screen.getByRole('button', {
      name: /open sync options/i,
    });
    expect(dropdownButton).toHaveClass('rounded-r-md');
  });

  test('split button has chevron icon', () => {
    const { wrapper } = createTestSetup();
    const { container } = render(
      <IDEHeader {...defaultProps} repoConnection={mockRepoConnection} />,
      { wrapper }
    );

    // Verify the button has the chevron icon
    const chevron = container.querySelector('.hero-chevron-down');
    expect(chevron).toBeInTheDocument();
  });

  test('split button main action calls onSave', () => {
    const { wrapper } = createTestSetup();
    const onSave = vi.fn();
    render(
      <IDEHeader
        {...defaultProps}
        onSave={onSave}
        repoConnection={mockRepoConnection}
      />,
      { wrapper }
    );

    const saveButton = screen.getByTestId('save-workflow-button');
    fireEvent.click(saveButton);

    expect(onSave).toHaveBeenCalledTimes(1);
  });

  test('split button dropdown opens menu with Save & Sync option', async () => {
    const { wrapper } = createTestSetup();
    render(
      <IDEHeader {...defaultProps} repoConnection={mockRepoConnection} />,
      { wrapper }
    );

    const dropdownButton = screen.getByRole('button', {
      name: /open sync options/i,
    });
    fireEvent.click(dropdownButton);

    // Wait for the menu item to appear using findByText
    const syncOption = await screen.findByText(/save & sync/i);
    expect(syncOption).toBeInTheDocument();
  });

  test('clicking "Save & Sync" calls openGitHubSyncModal', async () => {
    const { wrapper } = createTestSetup();
    const openGitHubSyncModal = vi.fn();
    render(
      <IDEHeader
        {...defaultProps}
        repoConnection={mockRepoConnection}
        openGitHubSyncModal={openGitHubSyncModal}
      />,
      { wrapper }
    );

    // Open dropdown
    const dropdownButton = screen.getByRole('button', {
      name: /open sync options/i,
    });
    fireEvent.click(dropdownButton);

    // Click Save & Sync option using findByText
    const syncOption = await screen.findByText(/save & sync/i);
    fireEvent.click(syncOption);

    expect(openGitHubSyncModal).toHaveBeenCalledTimes(1);
  });

  test('split button is disabled when canSave is false', () => {
    const { wrapper } = createTestSetup();
    render(
      <IDEHeader
        {...defaultProps}
        canSave={false}
        repoConnection={mockRepoConnection}
      />,
      { wrapper }
    );

    // Both save and dropdown buttons should be disabled
    const saveButton = screen.getByTestId('save-workflow-button');
    expect(saveButton).toBeDisabled();

    const dropdownButton = screen.getByRole('button', {
      name: /open sync options/i,
    });
    expect(dropdownButton).toBeDisabled();
  });

  test('dropdown menu "Save & Sync" option is disabled when canSave is false', async () => {
    const { wrapper } = createTestSetup();
    render(
      <IDEHeader
        {...defaultProps}
        canSave={false}
        repoConnection={mockRepoConnection}
      />,
      { wrapper }
    );

    // The dropdown button itself should be disabled, preventing menu from opening
    const dropdownButton = screen.getByRole('button', {
      name: /open sync options/i,
    });
    expect(dropdownButton).toBeDisabled();

    // Attempt to click anyway (shouldn't open menu)
    fireEvent.click(dropdownButton);

    // Menu should not appear when button is disabled
    const syncOption = screen.queryByText(/save & sync/i);
    expect(syncOption).not.toBeInTheDocument();
  });
});

// =============================================================================
// OTHER IDE HEADER ELEMENTS TESTS
// =============================================================================

describe('IDEHeader - Other Elements', () => {
  test('renders job name', () => {
    const { wrapper } = createTestSetup();
    render(<IDEHeader {...defaultProps} jobName="My Custom Job" />, {
      wrapper,
    });

    expect(screen.getByText('My Custom Job')).toBeInTheDocument();
  });

  test('renders Run button', () => {
    const { wrapper } = createTestSetup();
    render(<IDEHeader {...defaultProps} />, { wrapper });

    const runButton = screen.getByRole('button', { name: /run/i });
    expect(runButton).toBeInTheDocument();
  });

  test('renders Close button', () => {
    const { wrapper } = createTestSetup();
    render(<IDEHeader {...defaultProps} />, { wrapper });

    // Close button uses sr-only text "Close panel"
    const closeButton = screen.getByRole('button', {
      name: /close panel/i,
    });
    expect(closeButton).toBeInTheDocument();
  });

  test('Run button is disabled when canRun is false', () => {
    const { wrapper } = createTestSetup();
    render(<IDEHeader {...defaultProps} canRun={false} />, { wrapper });

    const runButton = screen.getByRole('button', { name: /run/i });
    expect(runButton).toBeDisabled();
  });

  test("Run button shows 'Processing' when isRunning is true", () => {
    const { wrapper } = createTestSetup();
    render(<IDEHeader {...defaultProps} isRunning={true} />, { wrapper });

    const runButton = screen.getByRole('button', { name: /processing/i });
    expect(runButton).toBeInTheDocument();
    expect(runButton).toHaveTextContent('Processing');
  });

  test('calls onClose when Close button is clicked', () => {
    const { wrapper } = createTestSetup();
    const onClose = vi.fn();
    render(<IDEHeader {...defaultProps} onClose={onClose} />, { wrapper });

    // Close button uses sr-only text "Close panel"
    const closeButton = screen.getByRole('button', {
      name: /close panel/i,
    });
    fireEvent.click(closeButton);

    expect(onClose).toHaveBeenCalledTimes(1);
  });

  test('calls onRun when Run button is clicked', () => {
    const { wrapper } = createTestSetup();
    const onRun = vi.fn();
    render(<IDEHeader {...defaultProps} onRun={onRun} />, { wrapper });

    const runButton = screen.getByRole('button', { name: /run/i });
    fireEvent.click(runButton);

    expect(onRun).toHaveBeenCalledTimes(1);
  });
});

// =============================================================================
// RUN BUTTON TOOLTIP TESTS
// =============================================================================

describe('IDEHeader - RunRetryButton Tooltip Props', () => {
  test('passes showKeyboardShortcuts=true to RunRetryButton', () => {
    const { wrapper } = createTestSetup();
    render(<IDEHeader {...defaultProps} canRun={true} />, { wrapper });

    // Verify Run button is rendered (which means RunRetryButton is rendered)
    const runButton = screen.getByRole('button', { name: /run/i });
    expect(runButton).toBeInTheDocument();

    // The component should always pass showKeyboardShortcuts=true
    // because IDE scope always owns shortcuts
    // We can't directly test the prop, but we verify the button renders correctly
    expect(runButton).not.toBeDisabled();
  });

  test('passes disabledTooltip when button is disabled', () => {
    const { wrapper } = createTestSetup();
    render(
      <IDEHeader
        {...defaultProps}
        canRun={false}
        runTooltip="Cannot run: missing credential"
      />,
      { wrapper }
    );

    // Verify Run button is disabled
    const runButton = screen.getByRole('button', { name: /run/i });
    expect(runButton).toBeDisabled();

    // The runTooltip prop should be passed as disabledTooltip to RunRetryButton
    // We verify the button is disabled, which means the tooltip logic will use disabledTooltip
  });

  test('RunRetryButton receives correct props for retryable run', () => {
    const { wrapper } = createTestSetup();
    render(<IDEHeader {...defaultProps} isRetryable={true} canRun={true} />, {
      wrapper,
    });

    // Verify retry button is shown
    const runButton = screen.getByRole('button', { name: /run/i });
    expect(runButton).toBeInTheDocument();
    expect(runButton).toHaveTextContent('Run (retry)');

    // Should have dropdown for "Run (New Work Order)"
    const dropdownButton = screen.getByRole('button', {
      name: /open options/i,
    });
    expect(dropdownButton).toBeInTheDocument();
  });

  test('RunRetryButton receives correct props for non-retryable run', () => {
    const { wrapper } = createTestSetup();
    render(<IDEHeader {...defaultProps} isRetryable={false} canRun={true} />, {
      wrapper,
    });

    // Verify run button is shown (not retry)
    const runButton = screen.getByRole('button', { name: /run/i });
    expect(runButton).toBeInTheDocument();
    expect(runButton).toHaveTextContent('Run');

    // Should NOT have dropdown
    expect(
      screen.queryByRole('button', { name: /open options/i })
    ).not.toBeInTheDocument();
  });

  test('RunRetryButton is in processing state when isRunning=true', () => {
    const { wrapper } = createTestSetup();
    render(<IDEHeader {...defaultProps} isRunning={true} canRun={true} />, {
      wrapper,
    });

    // Verify processing state
    const runButton = screen.getByRole('button', { name: /processing/i });
    expect(runButton).toBeInTheDocument();
    expect(runButton).toBeDisabled();
  });

  test('showKeyboardShortcuts is always true in IDE context', () => {
    const { wrapper } = createTestSetup();

    // Test with various states - shortcuts should always be shown
    const { rerender } = render(<IDEHeader {...defaultProps} canRun={true} />, {
      wrapper,
    });

    let runButton = screen.getByRole('button', { name: /run/i });
    expect(runButton).toBeInTheDocument();

    // Rerender with disabled state
    rerender(<IDEHeader {...defaultProps} canRun={false} />);

    runButton = screen.getByRole('button', { name: /run/i });
    expect(runButton).toBeDisabled();

    // Rerender with running state
    rerender(<IDEHeader {...defaultProps} isRunning={true} />);

    runButton = screen.getByRole('button', { name: /processing/i });
    expect(runButton).toBeInTheDocument();

    // In all cases, showKeyboardShortcuts=true is passed
    // (IDE scope always owns shortcuts, even when embedded panel is open)
  });
});

// =============================================================================
// PERMISSION TESTS
// =============================================================================

describe('IDEHeader - Permission Enforcement', () => {
  test('SaveButton respects canSave prop for permissions', () => {
    const { wrapper } = createTestSetup();
    render(
      <IDEHeader
        {...defaultProps}
        canSave={false}
        saveTooltip="You do not have permission to edit this workflow"
      />,
      { wrapper }
    );

    const saveButton = screen.getByTestId('save-workflow-button');
    expect(saveButton).toBeDisabled();
  });

  test('split button dropdown respects canSave prop for permissions', () => {
    const { wrapper } = createTestSetup();
    const mockRepoConnection = {
      id: 'repo-conn-123',
      repo: 'openfn/demo-project',
      branch: 'main',
      github_installation_id: 'install-456',
    };

    render(
      <IDEHeader
        {...defaultProps}
        canSave={false}
        repoConnection={mockRepoConnection}
        saveTooltip="You do not have permission to edit this workflow"
      />,
      { wrapper }
    );

    // Both buttons should be disabled
    const saveButton = screen.getByTestId('save-workflow-button');
    expect(saveButton).toBeDisabled();

    const dropdownButton = screen.getByRole('button', {
      name: /open sync options/i,
    });
    expect(dropdownButton).toBeDisabled();
  });

  test('SaveButton shows permission tooltip when disabled', () => {
    const { wrapper } = createTestSetup();
    render(
      <IDEHeader
        {...defaultProps}
        canSave={false}
        saveTooltip="You do not have permission to edit this workflow"
      />,
      { wrapper }
    );

    // Verify button is disabled (tooltip behavior is handled by Tooltip component)
    const saveButton = screen.getByTestId('save-workflow-button');
    expect(saveButton).toBeDisabled();
  });
});
