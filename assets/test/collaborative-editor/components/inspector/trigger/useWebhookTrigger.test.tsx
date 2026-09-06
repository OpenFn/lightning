/**
 * useWebhookTrigger Hook Tests
 *
 * Tests the shared webhook-trigger hook: URL derivation, the auth-methods load
 * effect, and the channel-backed commitAuthMethods helper (success + failure).
 */

import { renderHook, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import * as Y from 'yjs';

import { useWebhookTrigger } from '../../../../../js/collaborative-editor/components/inspector/trigger/useWebhookTrigger';
import type { WorkflowStoreInstance } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Workflow } from '../../../../../js/collaborative-editor/types/workflow';
import {
  createMockChannelPushError,
  createMockChannelPushOk,
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../../__helpers__/channelMocks';
import { createTriggerTestHarness } from '../../../__helpers__/triggerInspectorHelpers';

const TRIGGER_ID = '11111111-1111-4111-8111-111111111111';
const PROJECT = { id: '22222222-2222-4222-8222-222222222222', name: 'ET EMR' };

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
    const { wrapper } = await createTriggerTestHarness({ workflowStore });

    const { result } = renderHook(() => useWebhookTrigger(trigger), {
      wrapper,
    });

    expect(result.current.endpoints).toEqual([
      {
        url: `${window.location.origin}/i/${TRIGGER_ID}`,
        label: 'Default',
        generated: true,
      },
    ]);
    // Until the store reports methods for this trigger, it is loading.
    expect(result.current.loadingAuthMethods).toBe(true);
    expect(result.current.triggerAuthMethods).toEqual([]);

    await waitFor(() => {
      expect(requestSpy).toHaveBeenCalledWith(TRIGGER_ID);
    });
  });

  test('addresses a custom path within its project', async () => {
    ydoc.getArray('triggers').get(0).set('custom_path', 'facility-001');
    const withPath = workflowStore.getSnapshot().triggers[0];

    const { wrapper } = await createTriggerTestHarness({
      workflowStore,
      project: PROJECT,
    });

    const { result } = renderHook(() => useWebhookTrigger(withPath), {
      wrapper,
    });

    // Naming a webhook adds an address, it never replaces the default, and the
    // default is listed first because it is the one that cannot change.
    expect(result.current.endpoints.map(e => e.url)).toEqual([
      `${window.location.origin}/i/${TRIGGER_ID}`,
      `${window.location.origin}/i/${PROJECT.id}/facility-001`,
    ]);
  });

  test('leaves a usable path raw', async () => {
    // The server compares raw segments, so encoding here would stop a path
    // holding a percent sequence from matching.
    ydoc.getArray('triggers').get(0).set('custom_path', 'facility-001');
    const withPath = workflowStore.getSnapshot().triggers[0];

    const { wrapper } = await createTriggerTestHarness({
      workflowStore,
      project: PROJECT,
    });

    const { result } = renderHook(() => useWebhookTrigger(withPath), {
      wrapper,
    });

    expect(result.current.endpoints[1]?.url).toBe(
      `${window.location.origin}/i/${PROJECT.id}/facility-001`
    );
  });

  test('lists only the generated URL when the stored path is not addressable', async () => {
    // Stored verbatim, but the lookup only matches one segment, so this URL
    // would 404 and hide the one that works.
    ydoc.getArray('triggers').get(0).set('custom_path', 'v1/orders');
    const legacy = workflowStore.getSnapshot().triggers[0];

    const { wrapper } = await createTriggerTestHarness({
      workflowStore,
      project: PROJECT,
    });

    const { result } = renderHook(() => useWebhookTrigger(legacy), { wrapper });

    expect(result.current.endpoints.map(e => e.url)).toEqual([
      `${window.location.origin}/i/${TRIGGER_ID}`,
    ]);
  });

  test('falls back to the trigger id when the project is unknown', async () => {
    ydoc.getArray('triggers').get(0).set('custom_path', 'facility-001');
    const withPath = workflowStore.getSnapshot().triggers[0];

    const { wrapper } = await createTriggerTestHarness({ workflowStore });

    const { result } = renderHook(() => useWebhookTrigger(withPath), {
      wrapper,
    });

    expect(result.current.endpoints.map(e => e.url)).toEqual([
      `${window.location.origin}/i/${TRIGGER_ID}`,
    ]);
  });

  test('commitAuthMethods issues the update channel request', async () => {
    const { wrapper, sessionChannel } = await createTriggerTestHarness({
      workflowStore,
    });
    sessionChannel.push = createMockChannelPushOk({ ok: true });

    const { result } = renderHook(() => useWebhookTrigger(trigger), {
      wrapper,
    });

    await result.current.commitAuthMethods(['auth-1', 'auth-2']);

    expect(sessionChannel.push).toHaveBeenCalledWith(
      'update_trigger_auth_methods',
      {
        trigger_id: TRIGGER_ID,
        auth_method_ids: ['auth-1', 'auth-2'],
      }
    );
  });

  test('commitAuthMethods rethrows when the channel request fails', async () => {
    const { wrapper, sessionChannel } = await createTriggerTestHarness({
      workflowStore,
    });
    sessionChannel.push = createMockChannelPushError(
      'Permission denied',
      'error'
    );

    const { result } = renderHook(() => useWebhookTrigger(trigger), {
      wrapper,
    });

    await expect(
      result.current.commitAuthMethods(['auth-1'])
    ).rejects.toThrow();
  });
});
