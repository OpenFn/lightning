/**
 * Trigger Inspector Test Harness
 *
 * Shared setup factory for all trigger inspector test files. Wires the session
 * store, session-context store, and workflow store in exactly the way the five
 * consuming test files previously duplicated in their local `setup()` functions.
 *
 * Usage:
 *   const { wrapper, sessionContextStore, workflowStore } =
 *     await createTriggerTestHarness({ canEdit: true });
 *
 *   render(<MyComponent />, { wrapper });
 *
 * The factory does NOT render anything — each test file renders its own subject.
 */

import type React from 'react';
import { act } from 'react';
import { vi } from 'vitest';

import { LiveViewActionsProvider } from '../../../js/collaborative-editor/contexts/LiveViewActionsContext';
import { SessionContext } from '../../../js/collaborative-editor/contexts/SessionProvider';
import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import type { SessionContextStoreInstance } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionStore } from '../../../js/collaborative-editor/stores/createSessionStore';
import type { SessionStore } from '../../../js/collaborative-editor/stores/createSessionStore';
import { createUIStore } from '../../../js/collaborative-editor/stores/createUIStore';
import type { WorkflowStoreInstance } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import type { WebhookAuthMethod } from '../../../js/collaborative-editor/types/sessionContext';

import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  createMockChannelPushOk,
} from './channelMocks';
import { createMockSocket } from './sessionStoreHelpers';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface TriggerTestHarnessOptions {
  /** Whether the session-context emits can_edit_workflow=true (default: true). */
  canEdit?: boolean;
  /** Whether the session-context emits kafka_triggers_enabled=true (default: false). */
  kafkaEnabled?: boolean;
  /**
   * Project-level webhook auth methods emitted in the session_context event.
   * Defaults to an empty array.
   */
  webhookAuthMethods?: WebhookAuthMethod[];
  /**
   * A pre-connected WorkflowStoreInstance to include in the context.
   * When omitted the harness does NOT include a workflowStore — pass one from
   * the test's own `createConnectedWorkflowStore()` call.
   */
  workflowStore?: WorkflowStoreInstance;
  /**
   * LiveView actions to expose through LiveViewActionsProvider.
   * When omitted, a default set of `vi.fn()` mocks is used — the provider is
   * always present since useWorkflowActions() requires it unconditionally.
   */
  liveViewActions?: {
    pushEvent: ReturnType<typeof vi.fn>;
    pushEventTo: ReturnType<typeof vi.fn>;
    handleEvent: ReturnType<typeof vi.fn>;
    navigate: ReturnType<typeof vi.fn>;
  };
}

export interface TriggerTestHarness {
  /** React wrapper component for use as the `wrapper` option to `render` / `renderHook`. */
  wrapper: React.FC<{ children: React.ReactNode }>;
  /** The live session store (connected to a mock socket). */
  sessionStore: SessionStore;
  /** The session-context store (already received a `session_context` event). */
  sessionContextStore: SessionContextStoreInstance;
  /**
   * The session provider's channel, pre-configured to respond "ok" to any push.
   * Useful for inspecting `update_trigger_auth_methods` calls.
   */
  sessionChannel: { push: ReturnType<typeof createMockChannelPushOk> };
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

/**
 * Builds a fully-wired trigger inspector test harness.
 *
 * Steps performed (in order):
 * 1. Create + initialise a SessionStore with a mock socket.
 * 2. Wait 50 ms for the mock PhoenixChannelProvider to build its channel.
 * 3. Emit `sync` + `status` on the provider so the store is "connected".
 * 4. Configure the session channel to return ok for any push.
 * 5. Create a SessionContextStore, connect it to its own mock channel, and emit
 *    a `session_context` event with the requested permissions.
 * 6. Build a StoreContextValue from the provided workflowStore (if any).
 * 7. Return a `wrapper` React component that supplies all the required contexts.
 */
export async function createTriggerTestHarness(
  options: TriggerTestHarnessOptions = {}
): Promise<TriggerTestHarness> {
  const {
    canEdit = true,
    kafkaEnabled = false,
    webhookAuthMethods = [],
    workflowStore,
    liveViewActions,
  } = options;

  // 1. Session store
  const sessionStore = createSessionStore();
  sessionStore.initializeSession(
    createMockSocket(),
    'test:room',
    { id: 'user-1', name: 'Test', email: 'test@example.com', color: '#000' },
    { connect: true }
  );

  // 2. Allow the mock PhoenixChannelProvider to create its channel.
  await new Promise(resolve => setTimeout(resolve, 50));

  // 3. Emit sync + status so the store treats itself as connected.
  const provider = sessionStore.getSnapshot().provider;
  if (provider) {
    provider.emit('sync', [true]);
    provider.emit('status', [{ status: 'connected' }]);
  }

  // 4. Pre-configure the session channel to respond ok.
  const sessionChannel = provider?.channel as unknown as {
    push: ReturnType<typeof createMockChannelPushOk>;
  };
  sessionChannel.push = createMockChannelPushOk({ ok: true });

  // 5. Session context store — emit permissions via the mock channel.
  const sessionContextStore: SessionContextStoreInstance =
    createSessionContextStore();
  const ctxChannel = createMockPhoenixChannel();
  const ctxProvider = createMockPhoenixChannelProvider(ctxChannel);
  sessionContextStore._connectChannel(ctxProvider as never);

  act(() => {
    (
      ctxChannel as never as {
        _test: { emit: (e: string, m: unknown) => void };
      }
    )._test.emit('session_context', {
      user: null,
      project: null,
      config: {
        require_email_verification: false,
        kafka_triggers_enabled: kafkaEnabled,
      },
      permissions: {
        can_edit_workflow: canEdit,
        can_run_workflow: canEdit,
        can_write_webhook_auth_method: canEdit,
      },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: webhookAuthMethods,
      workflow_template: null,
      has_read_ai_disclaimer: false,
    });
  });

  // 6. Store context value (workflowStore may be undefined for hook-only tests).
  const storeValue = {
    ...(workflowStore ? { workflowStore } : {}),
    sessionContextStore,
    uiStore: createUIStore(),
  } as unknown as StoreContextValue;

  // 7. Wrapper component.
  const resolvedLiveViewActions = liveViewActions ?? {
    pushEvent: vi.fn(),
    pushEventTo: vi.fn(),
    handleEvent: vi.fn(() => vi.fn()),
    navigate: vi.fn(),
  };

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={{ sessionStore, isNewWorkflow: false }}>
      <LiveViewActionsProvider actions={resolvedLiveViewActions}>
        <StoreContext.Provider value={storeValue}>
          {children}
        </StoreContext.Provider>
      </LiveViewActionsProvider>
    </SessionContext.Provider>
  );

  return { wrapper, sessionStore, sessionContextStore, sessionChannel };
}
