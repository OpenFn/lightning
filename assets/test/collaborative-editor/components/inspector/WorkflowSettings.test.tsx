/**
 * WorkflowSettings Component Tests
 *
 * Tests for WorkflowSettings component covering:
 * - Project concurrency validation rules
 * - Workflow name field
 * - Enable job logs toggle
 * - Dynamic Zod schema validation
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type React from 'react';
import { act } from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type * as Y from 'yjs';

import { KeyboardProvider } from '#/collaborative-editor/keyboard';
import { WorkflowSettings } from '../../../../js/collaborative-editor/components/inspector/WorkflowSettings';
import { LiveViewActionsProvider } from '../../../../js/collaborative-editor/contexts/LiveViewActionsContext';
import { SessionContext } from '../../../../js/collaborative-editor/contexts/SessionProvider';
import type { StoreContextValue } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import type { AdaptorStoreInstance } from '../../../../js/collaborative-editor/stores/createAdaptorStore';
import { createAdaptorStore } from '../../../../js/collaborative-editor/stores/createAdaptorStore';
import type { AwarenessStoreInstance } from '../../../../js/collaborative-editor/stores/createAwarenessStore';
import { createAwarenessStore } from '../../../../js/collaborative-editor/stores/createAwarenessStore';
import type { CredentialStoreInstance } from '../../../../js/collaborative-editor/stores/createCredentialStore';
import { createCredentialStore } from '../../../../js/collaborative-editor/stores/createCredentialStore';
import type { SessionContextStoreInstance } from '../../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionContextStore } from '../../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionStore } from '../../../../js/collaborative-editor/stores/createSessionStore';
import type { WorkflowStoreInstance } from '../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../js/collaborative-editor/stores/createWorkflowStore';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../__helpers__/channelMocks';
import { createWorkflowYDoc } from '../../__helpers__/workflowFactory';

// Mock useURLState
vi.mock('#/react/lib/use-url-state', () => ({
  useURLState: () => ({
    params: {},
    updateSearchParams: vi.fn(),
  }),
}));

/**
 * Helper to create and connect a workflow store with Y.Doc
 */
function createConnectedWorkflowStore(ydoc: Y.Doc): WorkflowStoreInstance {
  const store = createWorkflowStore();
  const mockProvider = createMockPhoenixChannelProvider(
    createMockPhoenixChannel()
  );
  store.connect(ydoc, mockProvider as any);
  return store;
}

/**
 * Creates a React wrapper with store providers for component testing
 */
function createWrapper(
  workflowStore: WorkflowStoreInstance,
  credentialStore: CredentialStoreInstance,
  sessionContextStore: SessionContextStoreInstance,
  adaptorStore: AdaptorStoreInstance,
  awarenessStore: AwarenessStoreInstance
): React.ComponentType<{ children: React.ReactNode }> {
  const sessionStore = createSessionStore();

  const mockStoreValue: StoreContextValue = {
    workflowStore,
    credentialStore,
    sessionContextStore,
    adaptorStore,
    awarenessStore,
  };

  const mockLiveViewActions = {
    pushEvent: vi.fn(),
    pushEventTo: vi.fn(),
    handleEvent: vi.fn(() => vi.fn()),
    navigate: vi.fn(),
  };

  const mockSessionValue = {
    sessionStore,
    isNewWorkflow: false,
  };

  return ({ children }: { children: React.ReactNode }) => (
    <KeyboardProvider>
      <SessionContext.Provider value={mockSessionValue}>
        <LiveViewActionsProvider actions={mockLiveViewActions}>
          <StoreContext.Provider value={mockStoreValue}>
            {children}
          </StoreContext.Provider>
        </LiveViewActionsProvider>
      </SessionContext.Provider>
    </KeyboardProvider>
  );
}

/**
 * Setup function for each test
 */
function setupTest(projectConcurrency: number | null = null) {
  const ydoc = createWorkflowYDoc({
    jobs: {},
    triggers: {},
    edges: [],
  });

  // Add workflow metadata to Y.Doc
  const workflowMap = ydoc.getMap('workflow');
  workflowMap.set('id', '550e8400-e29b-41d4-a716-446655440000');
  workflowMap.set('name', 'Test Workflow');
  workflowMap.set('lock_version', 1);
  workflowMap.set('deleted_at', null);
  workflowMap.set('concurrency', null);
  workflowMap.set('enable_job_logs', true);

  const workflowStore = createConnectedWorkflowStore(ydoc);
  const credentialStore = createCredentialStore();
  const sessionContextStore = createSessionContextStore();
  const adaptorStore = createAdaptorStore();
  const awarenessStore = createAwarenessStore();

  // Mock session context with project concurrency
  const mockChannel = createMockPhoenixChannel();
  sessionContextStore._connectChannel(
    createMockPhoenixChannelProvider(mockChannel) as any
  );

  act(() => {
    mockChannel._test.emit('session_context', {
      user: {
        id: '550e8400-e29b-41d4-a716-446655440000',
        first_name: 'Test',
        last_name: 'User',
        email: 'test@example.com',
        email_confirmed: true,
        support_user: false,
        inserted_at: '2024-01-15T10:30:00Z',
      },
      project: {
        id: '660e8400-e29b-41d4-a716-446655440000',
        name: 'Test Project',
        concurrency: projectConcurrency,
      },
      config: { require_email_verification: false },
      permissions: {
        can_edit_workflow: true,
        can_run_workflow: true,
        can_write_webhook_auth_method: true,
      },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: [],
      workflow_template: null,
      has_read_ai_disclaimer: true,
    });
  });

  const wrapper = createWrapper(
    workflowStore,
    credentialStore,
    sessionContextStore,
    adaptorStore,
    awarenessStore
  );

  return { workflowStore, ydoc, wrapper, sessionContextStore };
}

describe('WorkflowSettings - Project Concurrency Validation', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test('displays workflow name field with current value', async () => {
    const { wrapper } = setupTest();

    render(<WorkflowSettings />, { wrapper });

    await waitFor(
      () => {
        const nameInput = screen.getByLabelText('Workflow Name');
        expect(nameInput).toBeInTheDocument();
        expect(nameInput).toHaveValue('Test Workflow');
      },
      { timeout: 2000 }
    );
  });

  test('displays concurrency input without max when project concurrency is null', async () => {
    const { wrapper } = setupTest(null);

    render(<WorkflowSettings />, { wrapper });

    await waitFor(() => {
      const concurrencyInput = screen.getByLabelText('Max Concurrency');
      expect(concurrencyInput).toBeInTheDocument();
      expect(concurrencyInput).not.toHaveAttribute('max');
      expect(concurrencyInput).not.toBeDisabled();
    });
  });

  test('sets max attribute when project concurrency is defined', async () => {
    const { wrapper } = setupTest(5);

    render(<WorkflowSettings />, { wrapper });

    await waitFor(() => {
      const concurrencyInput = screen.getByLabelText('Max Concurrency');
      expect(concurrencyInput).toHaveAttribute('max', '5');
    });
  });

  test('disables input and shows warning when project concurrency is 1', async () => {
    const { wrapper } = setupTest(1);

    render(<WorkflowSettings />, { wrapper });

    await waitFor(() => {
      const concurrencyInput = screen.getByLabelText('Max Concurrency');
      expect(concurrencyInput).toBeDisabled();
      expect(concurrencyInput).toHaveAttribute('max', '1');
    });

    expect(
      screen.getByText(
        /Parallel execution of runs is disabled for this project/
      )
    ).toBeInTheDocument();
    expect(screen.getByText('project setup')).toBeInTheDocument();
  });

  test('shows validation error when workflow concurrency exceeds project limit', async () => {
    const { wrapper, workflowStore } = setupTest(5);
    const user = userEvent.setup();

    render(<WorkflowSettings />, { wrapper });

    await waitFor(() => {
      expect(screen.getByLabelText('Max Concurrency')).toBeInTheDocument();
    });

    const concurrencyInput = screen.getByLabelText('Max Concurrency');

    // Enter value exceeding project limit
    await act(async () => {
      await user.clear(concurrencyInput);
      await user.type(concurrencyInput, '10');
    });

    // Wait for validation error to appear
    await waitFor(() => {
      expect(
        screen.getByText('must not exceed project limit of 5')
      ).toBeInTheDocument();
    });
  });

  test('does not show validation error when workflow concurrency is within project limit', async () => {
    const { wrapper } = setupTest(5);
    const user = userEvent.setup();

    render(<WorkflowSettings />, { wrapper });

    await waitFor(() => {
      expect(screen.getByLabelText('Max Concurrency')).toBeInTheDocument();
    });

    const concurrencyInput = screen.getByLabelText('Max Concurrency');

    // Enter valid value
    await act(async () => {
      await user.clear(concurrencyInput);
      await user.type(concurrencyInput, '3');
    });

    // Wait a bit to ensure no error appears
    await waitFor(() => {
      expect(
        screen.queryByText(/must not exceed project limit/)
      ).not.toBeInTheDocument();
    });
  });

  test('accepts value equal to project concurrency limit', async () => {
    const { wrapper } = setupTest(5);
    const user = userEvent.setup();

    render(<WorkflowSettings />, { wrapper });

    await waitFor(() => {
      expect(screen.getByLabelText('Max Concurrency')).toBeInTheDocument();
    });

    const concurrencyInput = screen.getByLabelText('Max Concurrency');

    // Enter value equal to limit
    await act(async () => {
      await user.clear(concurrencyInput);
      await user.type(concurrencyInput, '5');
    });

    // Should not show validation error
    await waitFor(() => {
      expect(
        screen.queryByText(/must not exceed project limit/)
      ).not.toBeInTheDocument();
    });
  });

  test('clears validation error when value is corrected', async () => {
    const { wrapper } = setupTest(5);
    const user = userEvent.setup();

    render(<WorkflowSettings />, { wrapper });

    await waitFor(() => {
      expect(screen.getByLabelText('Max Concurrency')).toBeInTheDocument();
    });

    const concurrencyInput = screen.getByLabelText('Max Concurrency');

    // Enter invalid value
    await act(async () => {
      await user.clear(concurrencyInput);
      await user.type(concurrencyInput, '10');
    });

    // Wait for error
    await waitFor(() => {
      expect(
        screen.getByText('must not exceed project limit of 5')
      ).toBeInTheDocument();
    });

    // Correct the value
    await act(async () => {
      await user.clear(concurrencyInput);
      await user.type(concurrencyInput, '3');
    });

    // Error should be cleared
    await waitFor(() => {
      expect(
        screen.queryByText(/must not exceed project limit/)
      ).not.toBeInTheDocument();
    });
  });

  test('shows minimum value validation error', async () => {
    const { wrapper } = setupTest(5);
    const user = userEvent.setup();

    render(<WorkflowSettings />, { wrapper });

    await waitFor(() => {
      expect(screen.getByLabelText('Max Concurrency')).toBeInTheDocument();
    });

    const concurrencyInput = screen.getByLabelText('Max Concurrency');

    // Enter value below minimum (0)
    await act(async () => {
      await user.clear(concurrencyInput);
      await user.type(concurrencyInput, '0');
    });

    // Wait for validation error
    await waitFor(() => {
      expect(screen.getByText('must be at least 1')).toBeInTheDocument();
    });
  });

  test('displays enable job logs toggle', async () => {
    const { wrapper } = setupTest();

    render(<WorkflowSettings />, { wrapper });

    await waitFor(() => {
      expect(
        screen.getByLabelText('Allow console.log() usage')
      ).toBeInTheDocument();
    });
  });

  test('does not show warning message when project concurrency is greater than 1', async () => {
    const { wrapper } = setupTest(5);

    render(<WorkflowSettings />, { wrapper });

    await waitFor(() => {
      expect(screen.getByLabelText('Max Concurrency')).toBeInTheDocument();
    });

    expect(
      screen.queryByText(/Parallel execution of runs is disabled/)
    ).not.toBeInTheDocument();
  });
});
