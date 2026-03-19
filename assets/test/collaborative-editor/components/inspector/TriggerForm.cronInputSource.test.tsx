/**
 * TriggerForm Component Tests - Cron Input Source Field
 *
 * Tests for the cron_cursor_job_id (Cron Input Source) dropdown in TriggerForm.
 * This dropdown only appears for cron triggers and lets users pick which job's
 * output to use as input for cron-triggered runs.
 */

import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import type React from 'react';
import { act } from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import * as Y from 'yjs';

import { TriggerForm } from '../../../../js/collaborative-editor/components/inspector/TriggerForm';
import { SessionContext } from '../../../../js/collaborative-editor/contexts/SessionProvider';
import { LiveViewActionsProvider } from '../../../../js/collaborative-editor/contexts/LiveViewActionsContext';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { createAdaptorStore } from '../../../../js/collaborative-editor/stores/createAdaptorStore';
import { createAwarenessStore } from '../../../../js/collaborative-editor/stores/createAwarenessStore';
import { createCredentialStore } from '../../../../js/collaborative-editor/stores/createCredentialStore';
import { createSessionContextStore } from '../../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionStore } from '../../../../js/collaborative-editor/stores/createSessionStore';
import type { WorkflowStoreInstance } from '../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Session } from '../../../../js/collaborative-editor/types/session';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../__helpers__/channelMocks';
import { createSessionContext } from '../../__helpers__/sessionContextFactory';
import { createMockStoreContextValue } from '../../__helpers__/storeMocks';
import { createMockSocket } from '../../__helpers__/sessionStoreHelpers';

// ---------------------------------------------------------------------------
// Y.Doc factories
// ---------------------------------------------------------------------------

function createCronTriggerYDoc(
  opts: {
    cronCursorJobId?: string | null;
    jobs?: Array<{ id: string; name: string }>;
  } = {}
): Y.Doc {
  const ydoc = new Y.Doc();

  const triggersArray = ydoc.getArray('triggers');
  const triggerMap = new Y.Map();
  triggerMap.set('id', 'trigger-1');
  triggerMap.set('type', 'cron');
  triggerMap.set('enabled', true);
  triggerMap.set('cron_expression', '0 0 * * *');
  if (opts.cronCursorJobId !== undefined) {
    triggerMap.set('cron_cursor_job_id', opts.cronCursorJobId);
  }
  triggersArray.push([triggerMap]);

  const jobsArray = ydoc.getArray('jobs');
  for (const job of opts.jobs ?? []) {
    const jobMap = new Y.Map();
    jobMap.set('id', job.id);
    jobMap.set('name', job.name);
    jobMap.set('adaptor', '@openfn/language-common');
    jobMap.set('body', new Y.Text(''));
    jobMap.set('project_credential_id', null);
    jobMap.set('keychain_credential_id', null);
    jobsArray.push([jobMap]);
  }

  return ydoc;
}

function createTriggerYDoc(type: 'webhook' | 'kafka'): Y.Doc {
  const ydoc = new Y.Doc();
  const triggersArray = ydoc.getArray('triggers');
  const triggerMap = new Y.Map();
  triggerMap.set('id', 'trigger-1');
  triggerMap.set('type', type);
  triggerMap.set('enabled', true);
  triggersArray.push([triggerMap]);
  return ydoc;
}

// ---------------------------------------------------------------------------
// Store / wrapper helpers
// ---------------------------------------------------------------------------

function createConnectedWorkflowStore(ydoc: Y.Doc): WorkflowStoreInstance {
  const store = createWorkflowStore();
  const mockProvider = createMockPhoenixChannelProvider(
    createMockPhoenixChannel()
  );
  store.connect(ydoc as any, mockProvider as any);
  return store;
}

interface WrapperOptions {
  canEditWorkflow?: boolean;
}

function createWrapper(
  workflowStore: WorkflowStoreInstance,
  mockChannel: ReturnType<typeof createMockPhoenixChannel>,
  opts: WrapperOptions = {}
): React.ComponentType<{ children: React.ReactNode }> {
  const credentialStore = createCredentialStore();
  const sessionContextStore = createSessionContextStore();
  const adaptorStore = createAdaptorStore();
  const awarenessStore = createAwarenessStore();

  const mockProvider = createMockPhoenixChannelProvider(mockChannel);
  credentialStore._connectChannel(mockProvider as any);
  adaptorStore._connectChannel(mockProvider as any);
  sessionContextStore._connectChannel(mockProvider as any);

  const sessionContextData = createSessionContext({
    permissions: {
      can_edit_workflow: opts.canEditWorkflow ?? true,
      can_run_workflow: true,
      can_write_webhook_auth_method: true,
    },
  });

  act(() => {
    (mockChannel as any)._test.emit('session_context', sessionContextData);
  });

  const mockStoreValue = createMockStoreContextValue({
    workflowStore,
    credentialStore,
    sessionContextStore,
    adaptorStore,
    awarenessStore,
  });

  const mockLiveViewActions = {
    pushEvent: vi.fn(),
    pushEventTo: vi.fn(),
    handleEvent: vi.fn(() => vi.fn()),
    navigate: vi.fn(),
  };

  const sessionStore = createSessionStore();
  sessionStore.initializeSession(
    createMockSocket(),
    'test:room',
    { id: 'test-user', name: 'Test', email: 'test@example.com', color: '#000' },
    { connect: false }
  );
  const provider = sessionStore.getSnapshot().provider;
  if (provider) {
    provider.emit('sync', [true]);
    provider.emit('status', [{ status: 'connected' }]);
  }

  return ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={{ sessionStore, isNewWorkflow: false }}>
      <LiveViewActionsProvider actions={mockLiveViewActions}>
        <StoreContext.Provider value={mockStoreValue}>
          {children}
        </StoreContext.Provider>
      </LiveViewActionsProvider>
    </SessionContext.Provider>
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('TriggerForm - Cron Input Source dropdown', () => {
  let ydoc: Y.Doc;
  let workflowStore: WorkflowStoreInstance;
  let mockChannel: ReturnType<typeof createMockPhoenixChannel>;

  const JOB_1_ID = '11111111-1111-1111-1111-111111111111';
  const JOB_2_ID = '22222222-2222-2222-2222-222222222222';

  beforeEach(() => {
    ydoc = createCronTriggerYDoc({
      jobs: [
        { id: JOB_1_ID, name: 'Fetch Data' },
        { id: JOB_2_ID, name: 'Transform' },
      ],
    });
    workflowStore = createConnectedWorkflowStore(ydoc);
    mockChannel = createMockPhoenixChannel();
  });

  test(
    'renders for cron triggers with default option and all job options',
    { timeout: 15000 },
    async () => {
      const trigger = workflowStore.getSnapshot()
        .triggers[0] as Session.Trigger;

      render(<TriggerForm trigger={trigger} />, {
        wrapper: createWrapper(workflowStore, mockChannel),
      });

      const select = await screen.findByLabelText(
        'Cron Input Source',
        {},
        { timeout: 10000 }
      );
      expect(select).toBeInTheDocument();
      expect(
        screen.getByRole('option', { name: 'Final run state (default)' })
      ).toBeInTheDocument();
      expect(
        screen.getByRole('option', { name: 'Fetch Data' })
      ).toBeInTheDocument();
      expect(
        screen.getByRole('option', { name: 'Transform' })
      ).toBeInTheDocument();
      expect((select as HTMLSelectElement).value).toBe('');
    }
  );

  test('does not render for webhook or kafka triggers', async () => {
    for (const type of ['webhook', 'kafka'] as const) {
      const typeYdoc = createTriggerYDoc(type);
      const typeWorkflowStore = createConnectedWorkflowStore(typeYdoc);
      const typeMockChannel = createMockPhoenixChannel();
      const trigger = typeWorkflowStore.getSnapshot()
        .triggers[0] as unknown as Session.Trigger;

      const { unmount } = render(<TriggerForm trigger={trigger} />, {
        wrapper: createWrapper(typeWorkflowStore, typeMockChannel),
      });

      await waitFor(() => {
        expect(screen.getByLabelText('Trigger Type')).toBeInTheDocument();
      });
      expect(
        screen.queryByLabelText('Cron Input Source')
      ).not.toBeInTheDocument();

      unmount();
    }
  });

  test('reflects a pre-selected job id from the trigger', async () => {
    const preselectedYdoc = createCronTriggerYDoc({
      cronCursorJobId: JOB_2_ID,
      jobs: [
        { id: JOB_1_ID, name: 'Fetch Data' },
        { id: JOB_2_ID, name: 'Transform' },
      ],
    });
    const preselectedStore = createConnectedWorkflowStore(preselectedYdoc);
    const trigger = preselectedStore.getSnapshot()
      .triggers[0] as Session.Trigger;

    render(<TriggerForm trigger={trigger} />, {
      wrapper: createWrapper(preselectedStore, createMockPhoenixChannel()),
    });

    const select = (await screen.findByLabelText(
      'Cron Input Source'
    )) as HTMLSelectElement;
    expect(select.value).toBe(JOB_2_ID);
  });

  test('selecting a job updates the WorkflowStore', async () => {
    const trigger = workflowStore.getSnapshot().triggers[0] as Session.Trigger;

    render(<TriggerForm trigger={trigger} />, {
      wrapper: createWrapper(workflowStore, mockChannel),
    });

    const select = await screen.findByLabelText('Cron Input Source');
    expect((select as HTMLSelectElement).value).toBe('');

    fireEvent.change(select, { target: { value: JOB_1_ID } });

    await waitFor(() => {
      const snapshot = workflowStore.getSnapshot();
      const updatedTrigger = snapshot.triggers.find(t => t.id === 'trigger-1');
      expect((updatedTrigger as any)?.cron_cursor_job_id).toBe(JOB_1_ID);
    });
  });

  test('is disabled when the form is read-only', async () => {
    const trigger = workflowStore.getSnapshot().triggers[0] as Session.Trigger;

    render(<TriggerForm trigger={trigger} />, {
      wrapper: createWrapper(workflowStore, mockChannel, {
        canEditWorkflow: false,
      }),
    });

    const select = await screen.findByLabelText('Cron Input Source');
    expect(select).toBeDisabled();
  });

  test('select has aria-describedby linking to its description', async () => {
    const trigger = workflowStore.getSnapshot().triggers[0] as Session.Trigger;

    render(<TriggerForm trigger={trigger} />, {
      wrapper: createWrapper(workflowStore, mockChannel),
    });

    const select = await screen.findByLabelText('Cron Input Source');
    const describedBy = select.getAttribute('aria-describedby');
    expect(describedBy).toBeTruthy();
    expect(document.getElementById(describedBy!)).toBeInTheDocument();
  });
});
