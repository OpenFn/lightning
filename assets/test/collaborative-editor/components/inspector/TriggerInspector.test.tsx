/**
 * TriggerInspector Component Tests
 *
 * Tests for TriggerInspector's show-dispatch-by-type behaviour: each trigger
 * type should render its own resting ("show") panel, identifiable by its
 * distinctive heading. The legacy TriggerForm footer (Enabled toggle + Run
 * button) was removed in #4787 — those tests are no longer applicable.
 */

import { render, screen } from '@testing-library/react';
import type React from 'react';
import { act } from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type * as Y from 'yjs';

import { TriggerInspector } from '../../../../js/collaborative-editor/components/inspector/TriggerInspector';
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
import type { UIStoreInstance } from '../../../../js/collaborative-editor/stores/createUIStore';
import { createUIStore } from '../../../../js/collaborative-editor/stores/createUIStore';
import type { WorkflowStoreInstance } from '../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../js/collaborative-editor/stores/createWorkflowStore';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../__helpers__/channelMocks';
import { createMockSocket } from '../../__helpers__/sessionStoreHelpers';
import {
  createMockURLState,
  getURLStateMockValue,
} from '../../__helpers__/urlStateMocks';
import { createWorkflowYDoc } from '../../__helpers__/workflowFactory';

const urlState = createMockURLState();

vi.mock('../../../../js/react/lib/use-url-state', () => ({
  useURLState: () => getURLStateMockValue(urlState),
}));

// Mock useCanRun hook
vi.mock('../../../../js/collaborative-editor/hooks/useWorkflow', async () => {
  const actual = await vi.importActual(
    '../../../../js/collaborative-editor/hooks/useWorkflow'
  );
  return {
    ...actual,
    useCanRun: () => ({
      canRun: true,
      tooltipMessage: 'Run workflow',
    }),
  };
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function createConnectedWorkflowStore(ydoc: Y.Doc): WorkflowStoreInstance {
  const store = createWorkflowStore();
  const mockProvider = createMockPhoenixChannelProvider(
    createMockPhoenixChannel()
  );
  store.connect(ydoc, mockProvider as never);
  return store;
}

function createWrapper(
  workflowStore: WorkflowStoreInstance,
  credentialStore: CredentialStoreInstance,
  sessionContextStore: SessionContextStoreInstance,
  adaptorStore: AdaptorStoreInstance,
  awarenessStore: AwarenessStoreInstance,
  uiStore: UIStoreInstance
): React.ComponentType<{ children: React.ReactNode }> {
  const mockStoreValue: StoreContextValue = {
    workflowStore,
    credentialStore,
    sessionContextStore,
    adaptorStore,
    awarenessStore,
    uiStore,
  };

  const mockLiveViewActions = {
    pushEvent: vi.fn(),
    pushEventTo: vi.fn(),
    handleEvent: vi.fn(() => vi.fn()),
    navigate: vi.fn(),
  };

  const sessionStore = createSessionStore();
  const mockSocket = createMockSocket();
  sessionStore.initializeSession(
    mockSocket,
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
// Show-dispatch-by-type
// ---------------------------------------------------------------------------

describe('TriggerInspector — show dispatch by type', () => {
  let credentialStore: CredentialStoreInstance;
  let adaptorStore: AdaptorStoreInstance;
  let awarenessStore: AwarenessStoreInstance;
  let uiStore: UIStoreInstance;

  function makeSessionContextStore(triggerType: string): {
    sessionContextStore: SessionContextStoreInstance;
  } {
    const sessionContextStore = createSessionContextStore();
    const mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);
    sessionContextStore._connectChannel(mockProvider as never);

    act(() => {
      (
        mockChannel as never as {
          _test: { emit: (e: string, m: unknown) => void };
        }
      )._test.emit('session_context', {
        user: null,
        project: null,
        config: {
          require_email_verification: false,
          kafka_triggers_enabled: triggerType === 'kafka',
        },
        permissions: {
          can_edit_workflow: true,
          can_run_workflow: true,
          can_write_webhook_auth_method: true,
        },
        latest_snapshot_lock_version: 1,
        project_repo_connection: null,
        webhook_auth_methods: [],
        workflow_template: null,
      });
    });

    return { sessionContextStore };
  }

  beforeEach(() => {
    credentialStore = createCredentialStore();
    adaptorStore = createAdaptorStore();
    awarenessStore = createAwarenessStore();
    uiStore = createUIStore();
  });

  // Each row: [description, triggerType, extra trigger fields, expected heading]
  test.each<[string, string, Record<string, unknown>, string]>([
    [
      'webhook trigger renders WebhookShowPanel',
      'webhook',
      { enabled: true },
      'On webhook call',
    ],
    [
      'cron trigger renders CronShowPanel',
      'cron',
      { enabled: true, cron_expression: '0 9 * * *' },
      'On a schedule',
    ],
    [
      'kafka trigger renders KafkaShowPanel',
      'kafka',
      { enabled: true },
      'Kafka',
    ],
  ])('%s', (_, triggerType, extraFields, expectedHeading) => {
    const triggerId = `trigger-${triggerType}`;
    const ydoc = createWorkflowYDoc({
      triggers: {
        [triggerId]: { id: triggerId, type: triggerType, ...extraFields },
      },
    });
    ydoc.getMap('workflow').set('lock_version', 1);

    const workflowStore = createConnectedWorkflowStore(ydoc);
    const { sessionContextStore } = makeSessionContextStore(triggerType);
    const trigger = workflowStore.getSnapshot().triggers[0];

    render(
      <TriggerInspector
        trigger={trigger}
        onClose={vi.fn()}
        onOpenRunPanel={vi.fn()}
      />,
      {
        wrapper: createWrapper(
          workflowStore,
          credentialStore,
          sessionContextStore,
          adaptorStore,
          awarenessStore,
          uiStore
        ),
      }
    );

    expect(
      screen.getByRole('heading', { name: expectedHeading })
    ).toBeInTheDocument();
  });
});
