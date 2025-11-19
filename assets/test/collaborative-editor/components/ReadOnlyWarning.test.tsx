/**
 * ReadOnlyWarning Component Tests
 *
 * Tests for the ReadOnlyWarning component that displays a read-only indicator
 * in the workflow editor header when editing is restricted.
 *
 * Testing Focus: Verify component correctly shows/hides based on read-only state
 * from useWorkflowReadOnly hook. Since hook is thoroughly tested, we focus
 * on component rendering and user-visible behavior.
 */

import { act, render, screen, waitFor } from '@testing-library/react';
import type React from 'react';
import { describe, expect, test } from 'vitest';
import * as Y from 'yjs';

import { ReadOnlyWarning } from '../../../js/collaborative-editor/components/ReadOnlyWarning';
import { SessionContext } from '../../../js/collaborative-editor/contexts/SessionProvider';
import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionStore } from '../../../js/collaborative-editor/stores/createSessionStore';
import { createWorkflowStore } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Session } from '../../../js/collaborative-editor/types/session';
import { createSessionContext } from '../__helpers__/sessionContextFactory';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../mocks/phoenixChannel';
import { createMockSocket } from '../mocks/phoenixSocket';

// =============================================================================
// TEST HELPERS
// =============================================================================

interface WrapperOptions {
  permissions?: { can_edit_workflow: boolean; can_run_workflow: boolean };
  latestSnapshotLockVersion?: number;
  workflowLockVersion?: number | null;
  workflowDeletedAt?: string | null;
  isNewWorkflow?: boolean;
}

function createTestSetup(options: WrapperOptions = {}) {
  const {
    permissions = { can_edit_workflow: true, can_run_workflow: true },
    latestSnapshotLockVersion = 1,
    workflowLockVersion = 1,
    workflowDeletedAt = null,
    isNewWorkflow = false,
  } = options;

  const sessionStore = createSessionStore();
  const sessionContextStore = createSessionContextStore(isNewWorkflow);
  const workflowStore = createWorkflowStore();

  const ydoc = new Y.Doc() as Session.WorkflowDoc;
  const workflowMap = ydoc.getMap('workflow');

  // Only set id if not a new workflow (new workflows have no id yet)
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

  const mockChannel = createMockPhoenixChannel('test:room');
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);
  (mockProvider as any).doc = ydoc;

  workflowStore.connect(ydoc, mockProvider as any);
  sessionContextStore._connectChannel(mockProvider as any);

  // Initialize session store with mock socket - it starts connected
  const mockSocket = createMockSocket();
  sessionStore.initializeSession(mockSocket as any, 'test:room', null, {
    connect: true, // Ensure connected state
  });

  const emitSessionContext = () => {
    (mockChannel as any)._test.emit(
      'session_context',
      createSessionContext({
        permissions,
        latest_snapshot_lock_version: latestSnapshotLockVersion,
      })
    );
  };

  const mockStoreValue: StoreContextValue = {
    sessionContextStore,
    workflowStore,
    adaptorStore: {} as any,
    credentialStore: {} as any,
    awarenessStore: {} as any,
    uiStore: {} as any,
  };

  const mockSessionValue = {
    sessionStore,
    isNewWorkflow,
  };

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={mockSessionValue}>
      <StoreContext.Provider value={mockStoreValue}>
        {children}
      </StoreContext.Provider>
    </SessionContext.Provider>
  );

  return { wrapper, emitSessionContext, ydoc };
}

// =============================================================================
// COMPONENT RENDERING TESTS
// =============================================================================

describe('ReadOnlyWarning - Core Rendering', () => {
  test('renders warning with correct text when workflow is read-only', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    render(<ReadOnlyWarning />, { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.getByText('Read-only')).toBeInTheDocument();
    });
  });

  test('does not render when workflow is editable', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
    });

    render(<ReadOnlyWarning />, { wrapper });

    act(() => {
      emitSessionContext();
    });

<<<<<<< HEAD
    expect(screen.queryByText('Read-only')).not.toBeInTheDocument();
=======
    await waitFor(() => {
      expect(screen.queryByText('Read-only')).not.toBeInTheDocument();
    });
>>>>>>> bdcb847fb6 (Enable graceful degradation during workflow editor disconnection)
  });

  test('does not render during new workflow creation', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
      isNewWorkflow: true,
    });

    render(<ReadOnlyWarning />, { wrapper });

    act(() => {
      emitSessionContext();
    });

    expect(screen.queryByText('Read-only')).not.toBeInTheDocument();
  });
});

// =============================================================================
// COMPONENT PROPS TESTS
// =============================================================================

describe('ReadOnlyWarning - Props', () => {
  test('uses default ID when not specified', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    render(<ReadOnlyWarning />, { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const element = screen.getByText('Read-only').parentElement;
      expect(element).toHaveAttribute('id', 'edit-disabled-warning');
    });
  });

  test('accepts custom ID prop', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    render(<ReadOnlyWarning id="custom-id" />, { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const element = screen.getByText('Read-only').parentElement;
      expect(element).toHaveAttribute('id', 'custom-id');
    });
  });

  test('accepts custom className prop', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    render(<ReadOnlyWarning className="custom-class" />, { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const element = screen.getByText('Read-only').parentElement;
      expect(element).toHaveClass('custom-class');
    });
  });
});

// =============================================================================
// STYLING TESTS
// =============================================================================

describe('ReadOnlyWarning - Styling', () => {
  test('applies correct styling classes', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    render(<ReadOnlyWarning />, { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const element = screen.getByText('Read-only').parentElement;
      expect(element).toHaveClass('cursor-pointer');
      expect(element).toHaveClass('text-xs');
      expect(element).toHaveClass('flex');
      expect(element).toHaveClass('items-center');
    });
  });

  test('includes information icon with correct styling', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    render(<ReadOnlyWarning />, { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const container = screen.getByText('Read-only').parentElement;
      const icon = container?.querySelector('.hero-information-circle-solid');
      expect(icon).toBeInTheDocument();
      expect(icon).toHaveClass('h-4');
      expect(icon).toHaveClass('w-4');
      expect(icon).toHaveClass('text-primary-600');
      expect(icon).toHaveClass('opacity-50');
    });
  });

  test('text has correct spacing from icon', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    render(<ReadOnlyWarning />, { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      const textElement = screen.getByText('Read-only');
      expect(textElement).toHaveClass('ml-1');
    });
  });
});

// =============================================================================
// READ-ONLY STATE INTEGRATION TESTS
// =============================================================================

describe('ReadOnlyWarning - Read-Only States', () => {
  test('renders for deleted workflow', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      workflowDeletedAt: new Date().toISOString(),
    });

    render(<ReadOnlyWarning />, { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.getByText('Read-only')).toBeInTheDocument();
    });
  });

  test('renders for users without edit permission', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      permissions: { can_edit_workflow: false },
    });

    render(<ReadOnlyWarning />, { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.getByText('Read-only')).toBeInTheDocument();
    });
  });

  test('renders for old snapshots', async () => {
    const { wrapper, emitSessionContext } = createTestSetup({
      latestSnapshotLockVersion: 2,
      workflowLockVersion: 1,
    });

    render(<ReadOnlyWarning />, { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.getByText('Read-only')).toBeInTheDocument();
    });
  });
});

// =============================================================================
// DYNAMIC STATE CHANGES TESTS
// =============================================================================

describe('ReadOnlyWarning - Dynamic Changes', () => {
  test('appears when workflow becomes deleted', async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
    });

    const { rerender } = render(<ReadOnlyWarning />, { wrapper });

    act(() => {
      emitSessionContext();
    });

    await waitFor(() => {
      expect(screen.queryByText('Read-only')).not.toBeInTheDocument();
    });

    // Make workflow deleted
    act(() => {
      const workflowMap = ydoc.getMap('workflow');
      workflowMap.set('deleted_at', new Date().toISOString());
    });

    rerender(<ReadOnlyWarning />);

    await waitFor(() => {
      expect(screen.getByText('Read-only')).toBeInTheDocument();
    });
  });

  test('disappears when workflow is no longer deleted', async () => {
    const { wrapper, emitSessionContext, ydoc } = createTestSetup({
      permissions: { can_edit_workflow: true, can_run_workflow: true },
      workflowDeletedAt: new Date().toISOString(),
    });

    const { rerender } = render(<ReadOnlyWarning />, { wrapper });

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

    rerender(<ReadOnlyWarning />);

    await waitFor(() => {
      expect(screen.queryByText('Read-only')).not.toBeInTheDocument();
    });
  });
});
