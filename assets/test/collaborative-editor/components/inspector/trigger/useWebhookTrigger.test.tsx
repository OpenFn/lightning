/**
 * useWebhookTrigger Hook Tests
 *
 * Tests the shared webhook-trigger hook: URL derivation, the auth-methods load
 * effect, and the channel-backed commitAuthMethods helper (success + failure).
 */

import { renderHook, waitFor } from '@testing-library/react';
import type React from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import * as Y from 'yjs';

import { useWebhookTrigger } from '../../../../../js/collaborative-editor/components/inspector/trigger/useWebhookTrigger';
import { SessionContext } from '../../../../../js/collaborative-editor/contexts/SessionProvider';
import type { StoreContextValue } from '../../../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../../../js/collaborative-editor/contexts/StoreProvider';
import { createSessionContextStore } from '../../../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionStore } from '../../../../../js/collaborative-editor/stores/createSessionStore';
import { createUIStore } from '../../../../../js/collaborative-editor/stores/createUIStore';
import type { WorkflowStoreInstance } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Workflow } from '../../../../../js/collaborative-editor/types/workflow';
import {
  createMockChannelPushError,
  createMockChannelPushOk,
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../../__helpers__/channelMocks';
import { createMockSocket } from '../../../__helpers__/sessionStoreHelpers';

const TRIGGER_ID = '11111111-1111-4111-8111-111111111111';

function createWebhookTriggerYDoc(): Y.Doc {
  const ydoc = new Y.Doc();
  const triggersArray = ydoc.getArray('triggers');
  const triggerMap = new Y.Map();
  triggerMap.set('id', TRIGGER_ID);
  triggerMap.set('type', 'webhook');
  triggerMap.set('enabled', true);
  triggerMap.set('webhook_reply', 'before_start');
  triggersArray.push([triggerMap]);
  return ydoc;
}

function createConnectedWorkflowStore(ydoc: Y.Doc): WorkflowStoreInstance {
  const store = createWorkflowStore();
  const provider = createMockPhoenixChannelProvider(createMockPhoenixChannel());
  store.connect(ydoc, provider as never);
  return store;
}

/**
 * Builds a wrapper with a connected session (whose provider channel is
 * returned for push configuration) plus the store context.
 */
async function setup(workflowStore: WorkflowStoreInstance) {
  const sessionStore = createSessionStore();
  const mockSocket = createMockSocket();
  sessionStore.initializeSession(
    mockSocket,
    'test:room',
    { id: 'user-1', name: 'Test', email: 'test@example.com', color: '#000' },
    { connect: true }
  );

  // Allow the provider to create its channel before reading it.
  await new Promise(resolve => setTimeout(resolve, 50));

  const provider = sessionStore.getSnapshot().provider;
  if (provider) {
    provider.emit('sync', [true]);
    provider.emit('status', [{ status: 'connected' }]);
  }
  const channel = provider?.channel as unknown as {
    push: ReturnType<typeof createMockChannelPushOk>;
  };

  const storeValue = {
    workflowStore,
    sessionContextStore: createSessionContextStore(),
    uiStore: createUIStore(),
  } as unknown as StoreContextValue;

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={{ sessionStore, isNewWorkflow: false }}>
      <StoreContext.Provider value={storeValue}>
        {children}
      </StoreContext.Provider>
    </SessionContext.Provider>
  );

  return { wrapper, channel };
}

describe('useWebhookTrigger', () => {
  let ydoc: Y.Doc;
  let workflowStore: WorkflowStoreInstance;
  let trigger: Workflow.Trigger;

  beforeEach(() => {
    ydoc = createWebhookTriggerYDoc();
    workflowStore = createConnectedWorkflowStore(ydoc);
    trigger = workflowStore.getSnapshot().triggers[0];
  });

  test('derives the webhook URL from the trigger id and requests auth methods on mount', async () => {
    const requestSpy = vi.spyOn(workflowStore, 'requestTriggerAuthMethods');
    const { wrapper } = await setup(workflowStore);

    const { result } = renderHook(() => useWebhookTrigger(trigger), {
      wrapper,
    });

    expect(result.current.webhookUrl).toBe(
      `${window.location.origin}/i/${TRIGGER_ID}`
    );
    // Until the store reports methods for this trigger, it is loading.
    expect(result.current.loadingAuthMethods).toBe(true);
    expect(result.current.triggerAuthMethods).toEqual([]);

    await waitFor(() => {
      expect(requestSpy).toHaveBeenCalledWith(TRIGGER_ID);
    });
  });

  test('commitAuthMethods issues the update channel request', async () => {
    const { wrapper, channel } = await setup(workflowStore);
    channel.push = createMockChannelPushOk({ ok: true });

    const { result } = renderHook(() => useWebhookTrigger(trigger), {
      wrapper,
    });

    await result.current.commitAuthMethods(['auth-1', 'auth-2']);

    expect(channel.push).toHaveBeenCalledWith('update_trigger_auth_methods', {
      trigger_id: TRIGGER_ID,
      auth_method_ids: ['auth-1', 'auth-2'],
    });
  });

  test('commitAuthMethods rethrows when the channel request fails', async () => {
    const { wrapper, channel } = await setup(workflowStore);
    channel.push = createMockChannelPushError('Permission denied', 'error');

    const { result } = renderHook(() => useWebhookTrigger(trigger), {
      wrapper,
    });

    await expect(
      result.current.commitAuthMethods(['auth-1'])
    ).rejects.toThrow();
  });
});
