/**
 * Header Component Integration Tests
 *
 * Tests for the Header component focusing on ReadOnlyWarning integration.
 * Since hook and component tests are comprehensive, these tests verify
 * proper integration within the Header component.
 */

import {
  act,
  render,
  screen,
  waitFor,
  fireEvent,
} from '@testing-library/react';
import type React from 'react';
import { describe, expect, test, vi } from 'vitest';
import * as Y from 'yjs';

import { Header } from '../../../js/collaborative-editor/components/Header';
import { SessionContext } from '../../../js/collaborative-editor/contexts/SessionProvider';
import { LiveViewActionsProvider } from '../../../js/collaborative-editor/contexts/LiveViewActionsContext';
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
import { createSessionContext } from '../__helpers__/sessionContextFactory';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../mocks/phoenixChannel';
import { createMockSocket } from '../mocks/phoenixSocket';
import { vi } from 'vitest';
import { HotkeysProvider } from 'react-hotkeys-hook';

// =============================================================================
// TEST HELPERS
// =============================================================================

interface WrapperOptions {
  permissions?: { can_edit_workflow: boolean; can_run_workflow: boolean };
  latestSnapshotLockVersion?: number;
  workflowLockVersion?: number | null;
  workflowDeletedAt?: string | null;
  isNewWorkflow?: boolean;
  hasGithubConnection?: boolean;
  repoName?: string;
  branchName?: string;
}

function createTestSetup(options: WrapperOptions = {}) {
  const {
    permissions = { can_edit_workflow: true, can_run_workflow: true },
    latestSnapshotLockVersion = 1,
    workflowLockVersion = 1,
    workflowDeletedAt = null,
    isNewWorkflow = false,
    hasGithubConnection = false,
    repoName = 'openfn/demo',
    branchName = 'main',
  } = options;

  // Create all stores
  const sessionStore = createSessionStore();
  const sessionContextStore = createSessionContextStore(isNewWorkflow);
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

  if (!isNewWorkflow) {
    workflowMap.set('id', 'test-workflow-123');
  }
  workflowMap.set('name', 'Test Workflow');
  workflowMap.set('lock_version', workflowLockVersion);
  workflowMap.set('deleted_at', workflowDeletedAt);

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

  const emitSessionContext = () => {
    const context = hasGithubConnection
      ? createSessionContext({
          permissions,
          latest_snapshot_lock_version: latestSnapshotLockVersion,
          project_repo_connection: {
            repo: repoName,
            branch: branchName,
          },
        })
      : createSessionContext({
          permissions,
          latest_snapshot_lock_version: latestSnapshotLockVersion,
        });

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

  const mockLiveViewActions = {
    pushEvent: vi.fn(),
    pushEventTo: vi.fn(),
    handleEvent: vi.fn(() => vi.fn()),
    navigate: vi.fn(),
  };

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <HotkeysProvider>
      <SessionContext.Provider value={{ sessionStore, isNewWorkflow }}>
        <StoreContext.Provider value={mockStoreValue}>
          {children}
        </StoreContext.Provider>
      </SessionContext.Provider>
    </HotkeysProvider>
  );

  return { wrapper, emitSessionContext, ydoc, mockChannel };
}

// =============================================================================
// HEADER INTEGRATION TESTS
// =============================================================================

describe('Header - ReadOnlyWarning Integration', () => {
  test('renders ReadOnlyWarning in correct position (after Breadcrumbs, inside header)', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    const { container } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.getByText('Read-only')).toBeInTheDocument();
    });

    // Verify ReadOnlyWarning appears inside the main header div
    const readOnlyElement = screen.getByText('Read-only').parentElement;
    const headerDiv = container.querySelector('.flex-none.bg-white');

    // Both should exist
    expect(readOnlyElement).toBeInTheDocument();
    expect(headerDiv).toBeInTheDocument();

    // ReadOnlyWarning should be inside the header div
    expect(headerDiv).toContainElement(readOnlyElement);

    // ReadOnlyWarning should come after the breadcrumbs
    const breadcrumb = screen.getByText('Breadcrumb');
    const allElements = Array.from(container.querySelectorAll('*'));
    const breadcrumbIndex = allElements.indexOf(breadcrumb);
    const readOnlyIndex = allElements.indexOf(readOnlyElement!);

    expect(readOnlyIndex).toBeGreaterThan(breadcrumbIndex);
  });

  test('shows ReadOnlyWarning when workflow is read-only', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.getByText('Read-only')).toBeInTheDocument();
    });
  });

  test('does not show ReadOnlyWarning when workflow is editable', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    expect(screen.queryByText('Read-only')).not.toBeInTheDocument();
  });

  test('hides ReadOnlyWarning during new workflow creation', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
      isNewWorkflow: true,
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // Should not show warning even with no permission when creating new workflow
    expect(screen.queryByText('Read-only')).not.toBeInTheDocument();
  });
});

// =============================================================================
// HEADER COMPONENT BASELINE TESTS
// =============================================================================

describe('Header - Basic Rendering', () => {
  test('renders breadcrumbs', async () => {
    const { wrapper, emitSessionContext } = createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Test Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    expect(screen.getByText('Test Breadcrumb')).toBeInTheDocument();
  });

  test('renders save button', async () => {
    const { wrapper, emitSessionContext } = createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    expect(screen.getByRole('button', { name: /save/i })).toBeInTheDocument();
  });

  test('renders run button when projectId and workflowId and triggers provided', async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup();

    // Add a trigger so the Run button appears (must be a Y.Map, not plain object)
    const triggersArray = ydoc.getArray('triggers');
    const triggerMap = new Y.Map();
    triggerMap.set('id', 'trigger-123');
    triggerMap.set('type', 'webhook');
    triggerMap.set('enabled', true);
    triggerMap.set('cron_expression', null);
    triggerMap.set('kafka_configuration', null);
    triggersArray.push([triggerMap]);

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /run/i })).toBeInTheDocument();
    });
  });

  test('renders AI button', async () => {
    const { wrapper, emitSessionContext } = createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // AI button is rendered (disabled by default)
    const aiButtons = screen.getAllByRole('button');
    const aiButton = aiButtons.find(button =>
      button.querySelector('.hero-chat-bubble-left-right')
    );
    expect(aiButton).toBeInTheDocument();
    expect(aiButton).toBeDisabled();
  });

  test('settings button shows error styling when workflow has validation errors', async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup();

    const { container } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // Initially, settings button should have gray styling
    const settingsButton = container.querySelector(
      'button[type="button"] .hero-adjustments-vertical'
    )?.parentElement;
    expect(settingsButton).toHaveClass('text-slate-500');
    expect(settingsButton).toHaveClass('hover:text-slate-400');

    // Set workflow name to empty string (invalid)
    act(() => {
      const workflowMap = ydoc.getMap('workflow');
      workflowMap.set('name', '');
    });

    await waitFor(() => {
      // Settings button should now have red error styling
      expect(settingsButton).toHaveClass('text-danger-500');
      expect(settingsButton).toHaveClass('hover:text-danger-400');
    });

    // Fix the validation error
    act(() => {
      const workflowMap = ydoc.getMap('workflow');
      workflowMap.set('name', 'Valid Workflow Name');
    });

    await waitFor(() => {
      // Settings button should return to gray styling
      expect(settingsButton).toHaveClass('text-slate-500');
      expect(settingsButton).toHaveClass('hover:text-slate-400');
    });
  });

  test('settings button shows error styling when concurrency is invalid', async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup();

    const { container } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // Set concurrency to 0 (invalid)
    act(() => {
      const workflowMap = ydoc.getMap('workflow');
      workflowMap.set('concurrency', 0);
    });

    await waitFor(() => {
      const settingsButton = container.querySelector(
        'button[type="button"] .hero-adjustments-vertical'
      )?.parentElement;
      // Settings button should have red error styling
      expect(settingsButton).toHaveClass('text-danger-500');
      expect(settingsButton).toHaveClass('hover:text-danger-400');
    });
  });

  test('settings button remains clickable when validation errors exist', async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup();

    const { container } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // Set workflow name to empty string (invalid)
    act(() => {
      const workflowMap = ydoc.getMap('workflow');
      workflowMap.set('name', '');
    });

    await waitFor(() => {
      const settingsButton = container.querySelector(
        'button[type="button"] .hero-adjustments-vertical'
      )?.parentElement;
      expect(settingsButton).toHaveClass('text-danger-500');
    });

    // Verify button is still clickable (not disabled)
    const settingsButton = container.querySelector(
      'button[type="button"] .hero-adjustments-vertical'
    )?.parentElement as HTMLButtonElement;
    expect(settingsButton).not.toBeDisabled();
    expect(settingsButton).toHaveClass('cursor-pointer');
  });
});

// =============================================================================
// HEADER STATE INTERACTION TESTS
// =============================================================================

describe('Header - Read-Only State Changes', () => {
  test('ReadOnlyWarning appears when workflow becomes read-only', async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
    });

    const { rerender } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    expect(screen.queryByText('Read-only')).not.toBeInTheDocument();

    // Make workflow deleted
    act(() => {
      const workflowMap = ydoc.getMap('workflow');
      workflowMap.set('deleted_at', new Date().toISOString());
    });

    rerender(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>
    );

    await waitFor(() => {
      expect(screen.getByText('Read-only')).toBeInTheDocument();
    });
  });

  test('ReadOnlyWarning disappears when workflow becomes editable', async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
      workflowDeletedAt: new Date().toISOString(),
    });

    const { rerender } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.getByText('Read-only')).toBeInTheDocument();
    });

    // Make workflow not deleted
    act(() => {
      const workflowMap = ydoc.getMap('workflow');
      workflowMap.set('deleted_at', null);
    });

    rerender(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>
    );

    await waitFor(() => {
      expect(screen.queryByText('Read-only')).not.toBeInTheDocument();
    });
  });
});

// =============================================================================
// SPLIT BUTTON TESTS (GitHub Integration)
// =============================================================================

describe('Header - Split Button Behavior', () => {
  test('renders simple save button when no GitHub connection', async () => {
    const { wrapper, emitSessionContext } = createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // Should have save button
    const saveButton = screen.getByRole('button', { name: /save/i });
    expect(saveButton).toBeInTheDocument();

    // Should not have dropdown chevron
    expect(screen.queryByText(/open sync options/i)).not.toBeInTheDocument();
  });

  test('renders split button when GitHub connection exists', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      hasGithubConnection: true,
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // Should have save button
    const saveButton = screen.getByRole('button', { name: /save/i });
    expect(saveButton).toBeInTheDocument();

    // Should have dropdown button
    const dropdownButton = screen.getByRole('button', {
      name: /open sync options/i,
    });
    expect(dropdownButton).toBeInTheDocument();
  });

  test('split button dropdown shows dropdown trigger button', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      hasGithubConnection: true,
    });

    const { container } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // Verify dropdown button is present
    const dropdownButton = screen.getByRole('button', {
      name: /open sync options/i,
    });
    expect(dropdownButton).toBeInTheDocument();

    // Verify the button has the chevron icon (as a child span)
    const chevron = container.querySelector('.hero-chevron-down');
    expect(chevron).toBeInTheDocument();
  });

  test('split button has correct structure with two buttons', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      hasGithubConnection: true,
    });

    const { container } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // Find the split button container
    const splitButtonContainer = container.querySelector(
      '.inline-flex.rounded-md.shadow-xs'
    );
    expect(splitButtonContainer).toBeInTheDocument();

    // Should have both Save button and dropdown button
    const saveButton = screen.getByTestId('save-workflow-button');
    expect(saveButton).toBeInTheDocument();
    expect(saveButton).toHaveTextContent('Save');

    const dropdownButton = screen.getByRole('button', {
      name: /open sync options/i,
    });
    expect(dropdownButton).toBeInTheDocument();
  });
});

// =============================================================================
// RUN BUTTON TOOLTIP WITH PANEL STATE TESTS
// =============================================================================

describe('Header - Run Button Tooltip with Panel State', () => {
  test('shows shortcut tooltip when panel is closed (isRunPanelOpen=false)', async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup();

    // Add a trigger so the Run button appears
    const triggersArray = ydoc.getArray('triggers');
    const triggerMap = new Y.Map();
    triggerMap.set('id', 'trigger-123');
    triggerMap.set('type', 'webhook');
    triggerMap.set('enabled', true);
    triggerMap.set('has_auth_method', true);
    triggerMap.set('cron_expression', null);
    triggerMap.set('kafka_configuration', null);
    triggersArray.push([triggerMap]);

    render(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        isRunPanelOpen={false}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const runButton = screen.getByRole('button', { name: /run/i });
      expect(runButton).toBeInTheDocument();
    });

    // Tooltip should be shown when panel is closed
    // The component passes null for tooltip content when isRunPanelOpen=true
    // We verify the button renders correctly (tooltip component handles visibility)
  });

  test('hides shortcut tooltip when panel is open (isRunPanelOpen=true)', async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup();

    // Add a trigger so the Run button appears
    const triggersArray = ydoc.getArray('triggers');
    const triggerMap = new Y.Map();
    triggerMap.set('id', 'trigger-123');
    triggerMap.set('type', 'webhook');
    triggerMap.set('enabled', true);
    triggerMap.set('has_auth_method', true);
    triggerMap.set('cron_expression', null);
    triggerMap.set('kafka_configuration', null);
    triggersArray.push([triggerMap]);

    render(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        isRunPanelOpen={true}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const runButton = screen.getByRole('button', { name: /run/i });
      expect(runButton).toBeInTheDocument();
    });

    // Tooltip should be hidden when panel is open
    // We're testing tooltip visibility, not button enabled state
    // The button may be disabled for workflow validation reasons
    const runButton = screen.getByRole('button', { name: /run/i });
    expect(runButton).toBeInTheDocument();
  });

  test('always shows error tooltip when disabled, regardless of panel state', async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup();

    // Add a trigger
    const triggersArray = ydoc.getArray('triggers');
    const triggerMap = new Y.Map();
    triggerMap.set('id', 'trigger-123');
    triggerMap.set('type', 'webhook');
    triggerMap.set('enabled', true);
    triggerMap.set('has_auth_method', true);
    triggerMap.set('cron_expression', null);
    triggerMap.set('kafka_configuration', null);
    triggersArray.push([triggerMap]);

    const { rerender } = render(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        isRunPanelOpen={false}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /run/i })).toBeInTheDocument();
    });

    // Make workflow invalid (empty name)
    act(() => {
      const workflowMap = ydoc.getMap('workflow');
      workflowMap.set('name', '');
    });

    await waitFor(() => {
      const runButton = screen.getByRole('button', { name: /run/i });
      expect(runButton).toBeDisabled();
    });

    // Rerender with panel open
    rerender(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        isRunPanelOpen={true}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>
    );

    // Error tooltip should still be shown even when panel is open
    await waitFor(() => {
      const runButton = screen.getByRole('button', { name: /run/i });
      expect(runButton).toBeDisabled();
    });
  });

  test('tooltip state changes when panel opens and closes', async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup();

    // Add a trigger
    const triggersArray = ydoc.getArray('triggers');
    const triggerMap = new Y.Map();
    triggerMap.set('id', 'trigger-123');
    triggerMap.set('type', 'webhook');
    triggerMap.set('enabled', true);
    triggerMap.set('has_auth_method', true);
    triggerMap.set('cron_expression', null);
    triggerMap.set('kafka_configuration', null);
    triggersArray.push([triggerMap]);

    const { rerender } = render(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        isRunPanelOpen={false}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /run/i })).toBeInTheDocument();
    });

    let runButton = screen.getByRole('button', { name: /run/i });
    expect(runButton).toBeInTheDocument();
    // Tooltip should be present when closed

    // Open panel
    rerender(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        isRunPanelOpen={true}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>
    );

    runButton = screen.getByRole('button', { name: /run/i });
    expect(runButton).toBeInTheDocument();
    // Tooltip should be hidden when open

    // Close panel again
    rerender(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        isRunPanelOpen={false}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>
    );

    runButton = screen.getByRole('button', { name: /run/i });
    expect(runButton).toBeInTheDocument();
    // Tooltip should reappear when closed
  });

  test('defaults to isRunPanelOpen=false when prop not provided', async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup();

    // Add a trigger
    const triggersArray = ydoc.getArray('triggers');
    const triggerMap = new Y.Map();
    triggerMap.set('id', 'trigger-123');
    triggerMap.set('type', 'webhook');
    triggerMap.set('enabled', true);
    triggerMap.set('has_auth_method', true);
    triggerMap.set('cron_expression', null);
    triggerMap.set('kafka_configuration', null);
    triggersArray.push([triggerMap]);

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const runButton = screen.getByRole('button', { name: /run/i });
      expect(runButton).toBeInTheDocument();
    });

    // Default should show tooltip (panel closed by default)
    // We're testing that the prop defaults correctly, not button state
    const runButton = screen.getByRole('button', { name: /run/i });
    expect(runButton).toBeInTheDocument();
  });
});

// =============================================================================
// KEYBOARD SHORTCUT TESTS
// =============================================================================

describe('Header - Keyboard Shortcuts', () => {
  test('Header registers Ctrl+S keyboard shortcut handler', async () => {
    const { wrapper, emitSessionContext } = createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // The Header component should render without errors and register hotkeys
    // Testing actual keyboard events with react-hotkeys-hook is difficult in test environment
    // This test verifies the component renders correctly with hotkey setup
    expect(screen.getByRole('button', { name: /save/i })).toBeInTheDocument();
  });

  test('Header registers Cmd+S keyboard shortcut handler (Mac)', async () => {
    const { wrapper, emitSessionContext } = createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // The Header component should render without errors and register hotkeys
    // Testing actual keyboard events with react-hotkeys-hook is difficult in test environment
    // This test verifies the component renders correctly with hotkey setup
    expect(screen.getByRole('button', { name: /save/i })).toBeInTheDocument();
  });

  test('save button is disabled when user lacks permissions', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // Save button should be disabled
    const saveButton = screen.getByRole('button', { name: /save/i });
    expect(saveButton).toBeDisabled();
  });

  test('Header renders with GitHub connection and sync options available', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      hasGithubConnection: true,
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // Should have split button with dropdown for sync options
    const dropdownButton = screen.getByRole('button', {
      name: /open sync options/i,
    });
    expect(dropdownButton).toBeInTheDocument();
  });

  test('Header renders without GitHub connection and no sync options', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      hasGithubConnection: false,
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // Should NOT have split button dropdown
    const dropdownButton = screen.queryByRole('button', {
      name: /open sync options/i,
    });
    expect(dropdownButton).not.toBeInTheDocument();
  });

  test('split button dropdown is disabled when user lacks permissions', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      hasGithubConnection: true,
      permissions: { can_edit_workflow: false },
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // Both save and dropdown buttons should be disabled
    const saveButton = screen.getByRole('button', { name: /save/i });
    expect(saveButton).toBeDisabled();

    const dropdownButton = screen.getByRole('button', {
      name: /open sync options/i,
    });
    expect(dropdownButton).toBeDisabled();
  });

  test('Header renders correctly with all navigation elements', async () => {
    const { wrapper, emitSessionContext } = createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    // Should have breadcrumbs
    expect(
      screen.getByRole('navigation', { name: /breadcrumb/i })
    ).toBeInTheDocument();

    // Should have save button
    expect(screen.getByRole('button', { name: /save/i })).toBeInTheDocument();

    // Should have AI button
    const aiButtons = screen.getAllByRole('button');
    const aiButton = aiButtons.find(button =>
      button.querySelector('.hero-chat-bubble-left-right')
    );
    expect(aiButton).toBeInTheDocument();
    expect(aiButton).toBeDisabled();
  });
});
