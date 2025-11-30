/**
 * EdgeForm Component Tests
 *
 * Tests for EdgeForm component:
 * - Edge condition label, type, and expression fields
 * - Form value reset when switching between edges
 * - Collaborative validation integration
 */

import { render, screen, waitFor } from '@testing-library/react';
import type React from 'react';
import { act } from 'react';
import { beforeEach, describe, expect, test } from 'vitest';

import { EdgeForm } from '../../../../js/collaborative-editor/components/inspector/EdgeForm';
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
import type { Session } from '../../../../js/collaborative-editor/types/session';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../__helpers__/channelMocks';
import { createMockSocket } from '../../mocks/phoenixSocket';
import { createWorkflowYDoc } from '../../__helpers__/workflowFactory';

/**
 * Helper to create and connect a workflow store with Y.Doc
 */
function createConnectedWorkflowStore(
  ydoc: Session.WorkflowDoc
): WorkflowStoreInstance {
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
  // Create session store and initialize with mock socket
  const sessionStore = createSessionStore();
  const mockSocket = createMockSocket();
  sessionStore.initializeSession(mockSocket as any, 'test:room', null, {
    connect: true, // Ensure connected state
  });

  const mockStoreValue: StoreContextValue = {
    workflowStore,
    credentialStore,
    sessionContextStore,
    adaptorStore,
    awarenessStore,
    historyStore: {} as any,
    uiStore: {} as any,
    editorPreferencesStore: {} as any,
  };

  const mockSessionValue = {
    sessionStore,
    isNewWorkflow: false,
  };

  return ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={mockSessionValue}>
      <StoreContext.Provider value={mockStoreValue}>
        {children}
      </StoreContext.Provider>
    </SessionContext.Provider>
  );
}

describe('EdgeForm - Basic Rendering', () => {
  let ydoc: Session.WorkflowDoc;
  let workflowStore: WorkflowStoreInstance;
  let credentialStore: CredentialStoreInstance;
  let sessionContextStore: SessionContextStoreInstance;
  let adaptorStore: AdaptorStoreInstance;
  let awarenessStore: AwarenessStoreInstance;
  let mockChannel: any;

  beforeEach(() => {
    // Create Y.Doc with a simple workflow: trigger -> job-a -> job-b
    ydoc = createWorkflowYDoc({
      triggers: {
        'trigger-1': { id: 'trigger-1', type: 'webhook' },
      },
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
      },
      edges: [
        {
          id: 'edge-1',
          source: 'trigger-1',
          target: 'job-a',
          condition_type: 'always',
          condition_label: 'Trigger to Job A',
        },
        {
          id: 'edge-2',
          source: 'job-a',
          target: 'job-b',
          condition_type: 'on_job_success',
          condition_label: 'Job A to Job B',
        },
      ],
    }) as Session.WorkflowDoc;

    // Create connected stores
    workflowStore = createConnectedWorkflowStore(ydoc);
    credentialStore = createCredentialStore();
    sessionContextStore = createSessionContextStore();
    adaptorStore = createAdaptorStore();
    awarenessStore = createAwarenessStore();

    // Mock channel
    mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    credentialStore._connectChannel(mockProvider as any);
    adaptorStore._connectChannel(mockProvider as any);

    // Emit session context
    act(() => {
      (mockChannel as any)._test.emit('session_context', {
        user: null,
        project: null,
        config: { require_email_verification: false },
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        latest_snapshot_lock_version: 1,
      });
    });
  });

  test('renders edge form with label and condition fields', async () => {
    const edge = workflowStore.getSnapshot().edges[0];

    render(<EdgeForm edge={edge} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Check form fields exist
    expect(screen.getByLabelText('Label')).toBeInTheDocument();
    expect(screen.getByLabelText('Condition')).toBeInTheDocument();

    // Check initial values
    await waitFor(() => {
      expect(screen.getByDisplayValue('Trigger to Job A')).toBeInTheDocument();
    });
  });

  test('displays correct condition options for trigger edges', async () => {
    const edge = workflowStore.getSnapshot().edges[0]; // trigger -> job-a

    render(<EdgeForm edge={edge} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Trigger edges should only have "Always" and "On Match"
    const select = screen.getByLabelText('Condition');
    expect(select).toBeInTheDocument();

    // Check selected value
    await waitFor(() => {
      expect(screen.getByDisplayValue('Always')).toBeInTheDocument();
    });
  });

  test('displays correct condition options for job edges', async () => {
    const edge = workflowStore.getSnapshot().edges[1]; // job-a -> job-b

    render(<EdgeForm edge={edge} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Job edges should have all condition types
    const select = screen.getByLabelText('Condition');
    expect(select).toBeInTheDocument();

    // Check selected value is "On Success"
    await waitFor(() => {
      expect(screen.getByDisplayValue('On Success')).toBeInTheDocument();
    });
  });
});

describe('EdgeForm - Form Value Reset', () => {
  let ydoc: Session.WorkflowDoc;
  let workflowStore: WorkflowStoreInstance;
  let credentialStore: CredentialStoreInstance;
  let sessionContextStore: SessionContextStoreInstance;
  let adaptorStore: AdaptorStoreInstance;
  let awarenessStore: AwarenessStoreInstance;
  let mockChannel: any;

  beforeEach(() => {
    // Create Y.Doc with two edges with distinctly different values
    ydoc = createWorkflowYDoc({
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
        'job-c': {
          id: 'job-c',
          name: 'Job C',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
      },
      edges: [
        {
          id: 'edge-1',
          source: 'job-a',
          target: 'job-b',
          condition_type: 'on_job_success',
          condition_label: 'First Edge Label',
          condition_expression: undefined,
        },
        {
          id: 'edge-2',
          source: 'job-b',
          target: 'job-c',
          condition_type: 'js_expression',
          condition_label: 'Second Edge Label',
          condition_expression: 'state.data.success === true',
        },
      ],
    }) as Session.WorkflowDoc;

    // Create connected stores
    workflowStore = createConnectedWorkflowStore(ydoc);
    credentialStore = createCredentialStore();
    sessionContextStore = createSessionContextStore();
    adaptorStore = createAdaptorStore();
    awarenessStore = createAwarenessStore();

    // Mock channel
    mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    credentialStore._connectChannel(mockProvider as any);
    adaptorStore._connectChannel(mockProvider as any);

    // Emit session context
    act(() => {
      (mockChannel as any)._test.emit('session_context', {
        user: null,
        project: null,
        config: { require_email_verification: false },
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        latest_snapshot_lock_version: 1,
      });
    });
  });

  test('form values reset when switching between different edges', async () => {
    // This test verifies that TanStack Form properly re-initializes when
    // the edge prop changes, preventing form values from "sticking" between edges.
    // This is critical for collaborative editing where users frequently switch
    // between inspecting different edges.

    // Get both edges
    const edge1 = workflowStore
      .getSnapshot()
      .edges.find(e => e.id === 'edge-1');
    const edge2 = workflowStore
      .getSnapshot()
      .edges.find(e => e.id === 'edge-2');

    // Render form for edge-1
    const { rerender } = render(<EdgeForm edge={edge1!} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Verify edge-1 values are displayed initially
    await waitFor(() => {
      expect(screen.getByDisplayValue('First Edge Label')).toBeInTheDocument();
      expect(screen.getByDisplayValue('On Success')).toBeInTheDocument();
    });

    // Verify expression editor is NOT shown for edge-1
    expect(
      screen.queryByLabelText('Javascript Expression')
    ).not.toBeInTheDocument();

    // Now switch to edge-2 (this simulates user clicking on a different edge in the canvas)
    rerender(<EdgeForm edge={edge2!} />);

    // CRITICAL: Verify edge-2 values are displayed (not edge-1's values)
    // This is what we're testing - that form values don't "stick" when switching edges
    await waitFor(() => {
      expect(screen.getByDisplayValue('Second Edge Label')).toBeInTheDocument();
      // Verify edge-1's label is NOT shown
      expect(
        screen.queryByDisplayValue('First Edge Label')
      ).not.toBeInTheDocument();
    });

    // Verify condition type changed
    await waitFor(() => {
      expect(screen.getByDisplayValue('On Match')).toBeInTheDocument();
      // Verify edge-1's condition type is NOT shown
      expect(screen.queryByDisplayValue('On Success')).not.toBeInTheDocument();
    });

    // Verify expression editor is NOW shown for edge-2
    await waitFor(() => {
      expect(
        screen.getByLabelText('Javascript Expression')
      ).toBeInTheDocument();
      expect(
        screen.getByDisplayValue('state.data.success === true')
      ).toBeInTheDocument();
    });

    // Switch back to edge-1 to verify bidirectional switching works
    rerender(<EdgeForm edge={edge1!} />);

    // Verify edge-1 values are correctly restored
    await waitFor(() => {
      expect(screen.getByDisplayValue('First Edge Label')).toBeInTheDocument();
      expect(screen.getByDisplayValue('On Success')).toBeInTheDocument();
      // Verify edge-2's values are NOT shown
      expect(
        screen.queryByDisplayValue('Second Edge Label')
      ).not.toBeInTheDocument();
      expect(screen.queryByDisplayValue('On Match')).not.toBeInTheDocument();
    });

    // Verify expression editor is hidden again
    expect(
      screen.queryByLabelText('Javascript Expression')
    ).not.toBeInTheDocument();
  });
});

describe('EdgeForm - Collaborative Validation', () => {
  let ydoc: Session.WorkflowDoc;
  let workflowStore: WorkflowStoreInstance;
  let credentialStore: CredentialStoreInstance;
  let sessionContextStore: SessionContextStoreInstance;
  let adaptorStore: AdaptorStoreInstance;
  let awarenessStore: AwarenessStoreInstance;
  let mockChannel: any;

  beforeEach(() => {
    // Create Y.Doc with a simple edge
    ydoc = createWorkflowYDoc({
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
      },
      edges: [
        {
          id: 'edge-1',
          source: 'job-a',
          target: 'job-b',
          condition_type: 'on_job_success',
          condition_label: 'Test Edge',
        },
      ],
    }) as Session.WorkflowDoc;

    // Create connected stores
    workflowStore = createConnectedWorkflowStore(ydoc);
    credentialStore = createCredentialStore();
    sessionContextStore = createSessionContextStore();
    adaptorStore = createAdaptorStore();
    awarenessStore = createAwarenessStore();

    // Mock channel
    mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    credentialStore._connectChannel(mockProvider as any);
    adaptorStore._connectChannel(mockProvider as any);

    // Emit session context
    act(() => {
      (mockChannel as any)._test.emit('session_context', {
        user: null,
        project: null,
        config: { require_email_verification: false },
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        latest_snapshot_lock_version: 1,
      });
    });
  });

  test('displays server validation errors from Y.Doc', async () => {
    // Add server validation errors to Y.Doc
    const errorsMap = ydoc.getMap('errors');
    act(() => {
      ydoc.transact(() => {
        errorsMap.set('edges', {
          'edge-1': {
            condition_label: ['Label is too long (max 50 characters)'],
          },
        });
      });
    });

    const edge = workflowStore.getSnapshot().edges[0];

    render(<EdgeForm edge={edge} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Verify error is displayed in form
    await waitFor(() => {
      expect(screen.getByText(/Label is too long/)).toBeInTheDocument();
    });
  });

  test('clears errors when removed from Y.Doc', async () => {
    // Start with errors
    const errorsMap = ydoc.getMap('errors');
    act(() => {
      ydoc.transact(() => {
        errorsMap.set('edges', {
          'edge-1': {
            condition_label: ['Invalid label'],
          },
        });
      });
    });

    const edge = workflowStore.getSnapshot().edges[0];

    render(<EdgeForm edge={edge} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Verify error is shown
    await waitFor(() => {
      expect(screen.getByText(/Invalid label/)).toBeInTheDocument();
    });

    // Clear errors from Y.Doc
    act(() => {
      ydoc.transact(() => {
        errorsMap.set('edges', {});
      });
    });

    // Error should disappear
    await waitFor(() => {
      expect(screen.queryByText(/Invalid label/)).not.toBeInTheDocument();
    });
  });

  test('handles errors for specific edge only (not other edges)', async () => {
    // Create a second Y.Doc with two edges to test isolation
    const ydocWithTwoEdges = createWorkflowYDoc({
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
        'job-c': {
          id: 'job-c',
          name: 'Job C',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
      },
      edges: [
        {
          id: 'edge-1',
          source: 'job-a',
          target: 'job-b',
          condition_type: 'on_job_success',
          condition_label: 'Edge 1',
        },
        {
          id: 'edge-2',
          source: 'job-b',
          target: 'job-c',
          condition_type: 'on_job_success',
          condition_label: 'Edge 2',
        },
      ],
    });

    const twoEdgesStore = createConnectedWorkflowStore(
      ydocWithTwoEdges as Session.WorkflowDoc
    );

    // Add errors only for edge-2
    const errorsMap = ydocWithTwoEdges.getMap('errors');
    act(() => {
      ydocWithTwoEdges.transact(() => {
        errorsMap.set('edges', {
          'edge-2': {
            condition_label: ['Error on edge 2'],
          },
        });
      });
    });

    // Render form for edge-1
    const edge1 = twoEdgesStore
      .getSnapshot()
      .edges.find(e => e.id === 'edge-1');

    render(<EdgeForm edge={edge1!} />, {
      wrapper: createWrapper(
        twoEdgesStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // edge-1 form should NOT show edge-2's error
    await waitFor(() => {
      expect(screen.queryByText(/Error on edge 2/)).not.toBeInTheDocument();
    });
  });
});

describe('EdgeForm - Conditional Expression Validation', () => {
  let ydoc: Session.WorkflowDoc;
  let workflowStore: WorkflowStoreInstance;
  let credentialStore: CredentialStoreInstance;
  let sessionContextStore: SessionContextStoreInstance;
  let adaptorStore: AdaptorStoreInstance;
  let awarenessStore: AwarenessStoreInstance;
  let mockChannel: any;

  beforeEach(() => {
    // Create Y.Doc with an edge that has js_expression condition type
    ydoc = createWorkflowYDoc({
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
      },
      edges: [
        {
          id: 'edge-1',
          source: 'job-a',
          target: 'job-b',
          condition_type: 'js_expression',
          condition_expression: 'state.data.success === true',
          condition_label: 'Conditional Edge',
        },
      ],
    }) as Session.WorkflowDoc;

    // Create connected stores
    workflowStore = createConnectedWorkflowStore(ydoc);
    credentialStore = createCredentialStore();
    sessionContextStore = createSessionContextStore();
    adaptorStore = createAdaptorStore();
    awarenessStore = createAwarenessStore();

    // Mock channel
    mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    credentialStore._connectChannel(mockProvider as any);
    adaptorStore._connectChannel(mockProvider as any);

    // Emit session context
    act(() => {
      (mockChannel as any)._test.emit('session_context', {
        user: null,
        project: null,
        config: { require_email_verification: false },
        permissions: { can_edit_workflow: true, can_run_workflow: true },
        latest_snapshot_lock_version: 1,
      });
    });
  });

  test('shows expression field when condition_type is js_expression', async () => {
    const edge = workflowStore.getSnapshot().edges[0];

    render(<EdgeForm edge={edge} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Expression field should be visible for js_expression type
    await waitFor(() => {
      expect(
        screen.getByLabelText('Javascript Expression')
      ).toBeInTheDocument();
      expect(
        screen.getByDisplayValue('state.data.success === true')
      ).toBeInTheDocument();
    });
  });

  test('shows empty expression field for js_expression edges with empty value', async () => {
    // Create edge with empty expression
    const ydocEmptyExpr = createWorkflowYDoc({
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
      },
      edges: [
        {
          id: 'edge-1',
          source: 'job-a',
          target: 'job-b',
          condition_type: 'js_expression',
          condition_expression: '',
          condition_label: 'Conditional Edge',
        },
      ],
    });

    const storeEmptyExpr = createConnectedWorkflowStore(
      ydocEmptyExpr as Session.WorkflowDoc
    );
    const edge = storeEmptyExpr.getSnapshot().edges[0];

    render(<EdgeForm edge={edge} />, {
      wrapper: createWrapper(
        storeEmptyExpr,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    // Expression field should be visible but empty
    await waitFor(() => {
      expect(
        screen.getByLabelText('Javascript Expression')
      ).toBeInTheDocument();
      const textarea = screen.getByLabelText(
        'Javascript Expression'
      ) as HTMLTextAreaElement;
      expect(textarea.value).toBe('');
    });
  });

  test('renders expression field with valid content', async () => {
    const edge = workflowStore.getSnapshot().edges[0];

    render(<EdgeForm edge={edge} />, {
      wrapper: createWrapper(
        workflowStore,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    await waitFor(() => {
      expect(
        screen.getByLabelText('Javascript Expression')
      ).toBeInTheDocument();
      const textarea = screen.getByLabelText(
        'Javascript Expression'
      ) as HTMLTextAreaElement;
      // Verify it contains the expected expression
      expect(textarea.value).toBe('state.data.success === true');
    });
  });

  test('does not require condition_expression when condition_type is not js_expression', async () => {
    // Create edge with on_job_success condition type
    const ydocNoExpr = createWorkflowYDoc({
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
      },
      edges: [
        {
          id: 'edge-1',
          source: 'job-a',
          target: 'job-b',
          condition_type: 'on_job_success',
          condition_expression: undefined,
          condition_label: 'Success Edge',
        },
      ],
    });

    const storeNoExpr = createConnectedWorkflowStore(
      ydocNoExpr as Session.WorkflowDoc
    );
    const edge = storeNoExpr.getSnapshot().edges[0];

    render(<EdgeForm edge={edge} />, {
      wrapper: createWrapper(
        storeNoExpr,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    await waitFor(() => {
      expect(screen.getByDisplayValue('On Success')).toBeInTheDocument();
    });

    // Expression field should not be visible
    expect(
      screen.queryByLabelText('Javascript Expression')
    ).not.toBeInTheDocument();

    // Should not show any validation errors
    expect(screen.queryByText(/can't be blank/i)).not.toBeInTheDocument();
  });

  test('initializes with correct default value for condition_expression', async () => {
    // Start with on_job_success (no expression required)
    const ydocChanging = createWorkflowYDoc({
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
      },
      edges: [
        {
          id: 'edge-1',
          source: 'job-a',
          target: 'job-b',
          condition_type: 'on_job_success',
          condition_expression: undefined,
          condition_label: 'Changing Edge',
        },
      ],
    });

    const storeChanging = createConnectedWorkflowStore(
      ydocChanging as Session.WorkflowDoc
    );
    const edge = storeChanging.getSnapshot().edges[0];

    render(<EdgeForm edge={edge} />, {
      wrapper: createWrapper(
        storeChanging,
        credentialStore,
        sessionContextStore,
        adaptorStore,
        awarenessStore
      ),
    });

    await waitFor(() => {
      expect(screen.getByDisplayValue('On Success')).toBeInTheDocument();
    });

    // Expression field should not be visible for non-js_expression types
    expect(
      screen.queryByLabelText('Javascript Expression')
    ).not.toBeInTheDocument();
  });
});
