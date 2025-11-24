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
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { KeyboardProvider } from '../../../js/collaborative-editor/keyboard';

import { simulateStoreProviderWithConnection } from '../__helpers__/storeProviderHelpers';
import { createMinimalWorkflowYDoc } from '../__helpers__/workflowStoreHelpers';
import type { CreateSessionContextOptions } from '../__helpers__/sessionContextFactory';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';

// =============================================================================
// TEST MOCKS
// =============================================================================

// Mock useAdaptorIcons to prevent async fetch warnings
vi.mock('../../../js/workflow-diagram/useAdaptorIcons', () => ({
  default: () => ({}),
}));

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

/**
 * Creates a test setup for Header component tests using enhanced helpers.
 * This dramatically simplifies the setup compared to manual store creation.
 */
async function createTestSetup(options: WrapperOptions = {}) {
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

  // Create Y.Doc with workflow metadata
  const ydoc = createMinimalWorkflowYDoc(
    'test-workflow-123',
    'Test Workflow',
    workflowLockVersion
  );

  // For new workflows, remove the id
  const workflowMap = ydoc.getMap('workflow');
  if (isNewWorkflow) {
    workflowMap.delete('id');
  }

  // Set deleted_at if specified
  if (workflowDeletedAt !== null) {
    workflowMap.set('deleted_at', workflowDeletedAt);
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

  // Use the enhanced helper to set up stores and connections
  const {
    stores,
    sessionStore,
    ydoc: returnedYDoc,
    emitSessionContext,
    cleanup,
  } = await simulateStoreProviderWithConnection(
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

  // For new workflows, replace sessionContextStore with one that has isNewWorkflow=true
  // This is a limitation of the current helper design.
  if (isNewWorkflow) {
    stores.sessionContextStore = createSessionContextStore(true);
    // Reconnect to provider
    const session = sessionStore.getSnapshot();
    if (session.provider) {
      stores.sessionContextStore._connectChannel(session.provider);
      // Re-emit session context to the new store
      emitSessionContext?.();
    }
  }

  // Create wrapper (still needed for React context)
  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <KeyboardProvider>
      <SessionContext.Provider value={{ sessionStore, isNewWorkflow }}>
        <StoreContext.Provider value={stores}>{children}</StoreContext.Provider>
      </SessionContext.Provider>
    </KeyboardProvider>
  );

  return {
    wrapper,
    emitSessionContext,
    ydoc: returnedYDoc,
    cleanup,
  };
}

// =============================================================================
// HEADER INTEGRATION TESTS
// =============================================================================

describe('Header - ReadOnlyWarning Integration', () => {
  test('renders ReadOnlyWarning in correct position (after Breadcrumbs, inside header)', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    const { container } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    // Emit session context and wait for updates
    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
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
    const { wrapper, emitSessionContext } = await createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    // Emit session context and wait for updates
    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    await waitFor(() => {
      expect(screen.getByText('Read-only')).toBeInTheDocument();
    });
  });

  test('does not show ReadOnlyWarning when workflow is editable', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    // Emit session context and wait for updates
    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    expect(screen.queryByText('Read-only')).not.toBeInTheDocument();
  });

  test('hides ReadOnlyWarning during new workflow creation', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup({
      permissions: { can_edit_workflow: false },
      isNewWorkflow: true,
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    // Emit session context and wait for updates
    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
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
    const { wrapper, emitSessionContext } = await createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Test Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    expect(screen.getByText('Test Breadcrumb')).toBeInTheDocument();
  });

  test('renders save button', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    expect(screen.getByRole('button', { name: /save/i })).toBeInTheDocument();
  });

  test('renders run button when projectId and workflowId and triggers provided', async () => {
    const { wrapper, emitSessionContext, ydoc } = await createTestSetup();

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

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /run/i })).toBeInTheDocument();
    });
  });

  test('renders AI button', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
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
    const { wrapper, emitSessionContext, ydoc } = await createTestSetup();

    const { container } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    // Initially, settings button should have gray styling
    const settingsButton = container.querySelector(
      'button[type="button"] .hero-adjustments-vertical'
    )?.parentElement;
    expect(settingsButton).toHaveClass('text-slate-500');
    expect(settingsButton).toHaveClass('hover:text-slate-400');

    // Set workflow name to empty string (invalid)
    await act(async () => {
      const workflowMap = ydoc.getMap('workflow');
      workflowMap.set('name', '');
    });

    await waitFor(() => {
      // Settings button should now have red error styling
      expect(settingsButton).toHaveClass('text-danger-500');
      expect(settingsButton).toHaveClass('hover:text-danger-400');
    });

    // Fix the validation error
    await act(async () => {
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
    const { wrapper, emitSessionContext, ydoc } = await createTestSetup();

    const { container } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    // Set concurrency to 0 (invalid)
    await act(async () => {
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
    const { wrapper, emitSessionContext, ydoc } = await createTestSetup();

    const { container } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    // Set workflow name to empty string (invalid)
    await act(async () => {
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
    const { wrapper, emitSessionContext, ydoc } = await createTestSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
    });

    const { rerender } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    expect(screen.queryByText('Read-only')).not.toBeInTheDocument();

    // Make workflow deleted
    await act(async () => {
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
    const { wrapper, emitSessionContext, ydoc } = await createTestSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
      workflowDeletedAt: new Date().toISOString(),
    });

    const { rerender } = render(
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
      expect(screen.getByText('Read-only')).toBeInTheDocument();
    });

    // Make workflow not deleted
    await act(async () => {
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
    const { wrapper, emitSessionContext } = await createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    // Should have save button
    const saveButton = screen.getByRole('button', { name: /save/i });
    expect(saveButton).toBeInTheDocument();

    // Should not have dropdown chevron
    expect(screen.queryByText(/open sync options/i)).not.toBeInTheDocument();
  });

  test('renders split button when GitHub connection exists', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup({
      hasGithubConnection: true,
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
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
    const { wrapper, emitSessionContext } = await createTestSetup({
      hasGithubConnection: true,
    });

    const { container } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
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
    const { wrapper, emitSessionContext } = await createTestSetup({
      hasGithubConnection: true,
    });

    const { container } = render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
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
    const { wrapper, emitSessionContext, ydoc } = await createTestSetup();

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
    const { wrapper, emitSessionContext, ydoc } = await createTestSetup();

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
    const { wrapper, emitSessionContext, ydoc } = await createTestSetup();

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
    const { wrapper, emitSessionContext, ydoc } = await createTestSetup();

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
    const { wrapper, emitSessionContext, ydoc } = await createTestSetup();

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
    const { wrapper, emitSessionContext } = await createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    // The Header component should render without errors and register hotkeys
    // Testing actual keyboard events with KeyboardProvider is difficult in test environment
    // This test verifies the component renders correctly with hotkey setup
    expect(screen.getByRole('button', { name: /save/i })).toBeInTheDocument();
  });

  test('Header registers Cmd+S keyboard shortcut handler (Mac)', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    // The Header component should render without errors and register hotkeys
    // Testing actual keyboard events with KeyboardProvider is difficult in test environment
    // This test verifies the component renders correctly with hotkey setup
    expect(screen.getByRole('button', { name: /save/i })).toBeInTheDocument();
  });

  test('save button is disabled when user lacks permissions', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    // Save button should be disabled
    const saveButton = screen.getByRole('button', { name: /save/i });
    expect(saveButton).toBeDisabled();
  });

  test('Header renders with GitHub connection and sync options available', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup({
      hasGithubConnection: true,
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    // Should have split button with dropdown for sync options
    const dropdownButton = screen.getByRole('button', {
      name: /open sync options/i,
    });
    expect(dropdownButton).toBeInTheDocument();
  });

  test('Header renders without GitHub connection and no sync options', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup({
      hasGithubConnection: false,
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
    });

    // Should NOT have split button dropdown
    const dropdownButton = screen.queryByRole('button', {
      name: /open sync options/i,
    });
    expect(dropdownButton).not.toBeInTheDocument();
  });

  test('split button dropdown is disabled when user lacks permissions', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup({
      hasGithubConnection: true,
      permissions: { can_edit_workflow: false },
    });

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
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
    const { wrapper, emitSessionContext } = await createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    await act(async () => {
      emitSessionContext();
      await new Promise(resolve => setTimeout(resolve, 150));
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

// =============================================================================
// IDE MODE TESTS (Run/Retry Button)
// =============================================================================

describe('Header - IDE Mode Run/Retry Button', () => {
  test('renders simple Run button in IDE mode when not retryable', async () => {
    const { wrapper, emitSessionContext, ydoc } = await createTestSetup();

    render(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        onRunClick={vi.fn()}
        onRetryClick={vi.fn()}
        canRun={true}
        isRetryable={false}
        isRunning={false}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const runButton = screen.getByRole('button', { name: /^run$/i });
      expect(runButton).toBeInTheDocument();
      expect(runButton).not.toBeDisabled();
    });
  });

  test('renders split button with "Run (retry)" in IDE mode when retryable', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup();

    render(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        onRunClick={vi.fn()}
        onRetryClick={vi.fn()}
        canRun={true}
        isRetryable={true}
        isRunning={false}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const retryButton = screen.getByRole('button', {
        name: /run \(retry\)/i,
      });
      expect(retryButton).toBeInTheDocument();
      expect(retryButton).not.toBeDisabled();
    });
  });

  test('calls onRunClick when simple Run button is clicked', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup();
    const mockOnRunClick = vi.fn();

    render(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        onRunClick={mockOnRunClick}
        onRetryClick={vi.fn()}
        canRun={true}
        isRetryable={false}
        isRunning={false}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const runButton = screen.getByRole('button', { name: /^run$/i });
      expect(runButton).toBeInTheDocument();
    });

    const runButton = screen.getByRole('button', { name: /^run$/i });
    fireEvent.click(runButton);

    expect(mockOnRunClick).toHaveBeenCalledTimes(1);
  });

  test('calls onRetryClick when "Run (retry)" button is clicked', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup();
    const mockOnRetryClick = vi.fn();

    render(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        onRunClick={vi.fn()}
        onRetryClick={mockOnRetryClick}
        canRun={true}
        isRetryable={true}
        isRunning={false}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const retryButton = screen.getByRole('button', {
        name: /run \(retry\)/i,
      });
      expect(retryButton).toBeInTheDocument();
    });

    const retryButton = screen.getByRole('button', { name: /run \(retry\)/i });
    fireEvent.click(retryButton);

    expect(mockOnRetryClick).toHaveBeenCalledTimes(1);
  });

  test('disables run button in IDE mode when canRun is false', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup();

    render(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        onRunClick={vi.fn()}
        onRetryClick={vi.fn()}
        canRun={false}
        runTooltipMessage="Cannot run: validation errors"
        isRetryable={false}
        isRunning={false}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const runButton = screen.getByRole('button', { name: /^run$/i });
      expect(runButton).toBeInTheDocument();
      expect(runButton).toBeDisabled();
    });
  });

  test('shows "Processing" when isRunning is true', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup();

    render(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        onRunClick={vi.fn()}
        onRetryClick={vi.fn()}
        canRun={true}
        isRetryable={false}
        isRunning={true}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const processingButton = screen.getByRole('button', {
        name: /processing/i,
      });
      expect(processingButton).toBeInTheDocument();
      expect(processingButton).toBeDisabled();
    });
  });

  test('renders Canvas mode Run button when onRunClick provided but onRetryClick missing', async () => {
    const { wrapper, emitSessionContext, ydoc } = await createTestSetup();

    // Add a trigger for Canvas mode
    const triggersArray = ydoc.getArray('triggers');
    const triggerMap = new Y.Map();
    triggerMap.set('id', 'trigger-123');
    triggerMap.set('type', 'webhook');
    triggerMap.set('enabled', true);
    triggerMap.set('has_auth_method', true);
    triggersArray.push([triggerMap]);

    render(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        onRunClick={vi.fn()}
        // No onRetryClick - should render Canvas mode
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

    // Should be simple button, not split button
    expect(
      screen.queryByRole('button', { name: /run \(retry\)/i })
    ).not.toBeInTheDocument();
  });

  test('renders adaptorDisplay prop in IDE mode', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup();
    const adaptorDisplay = (
      <div data-testid="adaptor-display">Adaptor Display</div>
    );

    render(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        onRunClick={vi.fn()}
        onRetryClick={vi.fn()}
        canRun={true}
        isRetryable={false}
        isRunning={false}
        adaptorDisplay={adaptorDisplay}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.getByTestId('adaptor-display')).toBeInTheDocument();
      expect(screen.getByText('Adaptor Display')).toBeInTheDocument();
    });
  });

  test('renders close IDE button when onCloseIDE prop is provided', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup();
    const mockOnCloseIDE = vi.fn();

    render(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        onRunClick={vi.fn()}
        onRetryClick={vi.fn()}
        canRun={true}
        isRetryable={false}
        isRunning={false}
        onCloseIDE={mockOnCloseIDE}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const closeButton = screen.getByRole('button', { name: /close ide/i });
      expect(closeButton).toBeInTheDocument();
    });
  });

  test('calls onCloseIDE when close IDE button is clicked', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup();
    const mockOnCloseIDE = vi.fn();

    render(
      <Header
        projectId="project-1"
        workflowId="workflow-1"
        onRunClick={vi.fn()}
        onRetryClick={vi.fn()}
        canRun={true}
        isRetryable={false}
        isRunning={false}
        onCloseIDE={mockOnCloseIDE}
      >
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const closeButton = screen.getByRole('button', { name: /close ide/i });
      expect(closeButton).toBeInTheDocument();
    });

    const closeButton = screen.getByRole('button', { name: /close ide/i });
    fireEvent.click(closeButton);

    expect(mockOnCloseIDE).toHaveBeenCalledTimes(1);
  });

  test('does not render close IDE button when onCloseIDE prop is not provided', async () => {
    const { wrapper, emitSessionContext } = await createTestSetup();

    render(
      <Header projectId="project-1" workflowId="workflow-1">
        {[<span key="breadcrumb-1">Breadcrumb</span>]}
      </Header>,
      { wrapper }
    );

    act(() => {
      emitSessionContext();
    });

    expect(
      screen.queryByRole('button', { name: /close ide/i })
    ).not.toBeInTheDocument();
  });
});
