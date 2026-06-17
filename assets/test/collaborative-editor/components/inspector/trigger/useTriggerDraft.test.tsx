/**
 * useTriggerDraft Hook Tests
 *
 * Tests the draft/commit buffer used by the trigger edit wizard. The draft holds
 * edits locally; `updateTrigger` and `commitAuthMethods` must only fire from
 * `commit()`, and only when the relevant state actually changed.
 */

import { act, renderHook } from '@testing-library/react';
import type React from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import * as Y from 'yjs';

import { useTriggerDraft } from '../../../../../js/collaborative-editor/components/inspector/trigger/useTriggerDraft';
import type { StoreContextValue } from '../../../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../../../js/collaborative-editor/contexts/StoreProvider';
import { createSessionContextStore } from '../../../../../js/collaborative-editor/stores/createSessionContextStore';
import { createUIStore } from '../../../../../js/collaborative-editor/stores/createUIStore';
import type { WorkflowStoreInstance } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Workflow } from '../../../../../js/collaborative-editor/types/workflow';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../../__helpers__/channelMocks';

/**
 * Creates a Y.Doc with a single webhook trigger.
 */
const TRIGGER_ID = '11111111-1111-4111-8111-111111111111';

function createWebhookTriggerYDoc(): Y.Doc {
  const ydoc = new Y.Doc();
  const triggersArray = ydoc.getArray('triggers');
  const triggerMap = new Y.Map();
  triggerMap.set('id', TRIGGER_ID);
  triggerMap.set('type', 'webhook');
  triggerMap.set('enabled', true);
  triggerMap.set('webhook_reply', 'before_start');
  triggerMap.set('webhook_response_config', null);
  triggersArray.push([triggerMap]);
  return ydoc;
}

function createConnectedWorkflowStore(ydoc: Y.Doc): WorkflowStoreInstance {
  const store = createWorkflowStore();
  const provider = createMockPhoenixChannelProvider(createMockPhoenixChannel());
  store.connect(ydoc, provider as never);
  return store;
}

function createWrapper(
  workflowStore: WorkflowStoreInstance
): React.ComponentType<{ children: React.ReactNode }> {
  const storeValue = {
    workflowStore,
    sessionContextStore: createSessionContextStore(),
    uiStore: createUIStore(),
  } as unknown as StoreContextValue;

  return ({ children }: { children: React.ReactNode }) => (
    <StoreContext.Provider value={storeValue}>{children}</StoreContext.Provider>
  );
}

describe('useTriggerDraft', () => {
  let ydoc: Y.Doc;
  let workflowStore: WorkflowStoreInstance;
  let trigger: Workflow.Trigger;
  let commitAuthMethods: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    ydoc = createWebhookTriggerYDoc();
    workflowStore = createConnectedWorkflowStore(ydoc);
    trigger = workflowStore.getSnapshot().triggers[0];
    commitAuthMethods = vi.fn(async () => {});
  });

  function renderDraft(initialAuthMethodIds: string[] = []) {
    return renderHook(
      () =>
        useTriggerDraft(trigger, {
          initialAuthMethodIds,
          commitAuthMethods,
        }),
      { wrapper: createWrapper(workflowStore) }
    );
  }

  // Variant whose `initialAuthMethodIds` prop can change between renders, used
  // to exercise the async-load re-seed behaviour.
  function renderDraftWithProp(initialAuthMethodIds: string[] = []) {
    return renderHook(
      ({ ids }: { ids: string[] }) =>
        useTriggerDraft(trigger, {
          initialAuthMethodIds: ids,
          commitAuthMethods,
        }),
      {
        wrapper: createWrapper(workflowStore),
        initialProps: { ids: initialAuthMethodIds },
      }
    );
  }

  // Variant whose `trigger` prop can change between renders, used to simulate a
  // collaborator editing the trigger on the canvas while the wizard is open.
  function renderDraftWithTrigger(initialTrigger: Workflow.Trigger) {
    return renderHook(
      ({ t }: { t: Workflow.Trigger }) =>
        useTriggerDraft(t, {
          initialAuthMethodIds: [],
          commitAuthMethods,
        }),
      {
        wrapper: createWrapper(workflowStore),
        initialProps: { t: initialTrigger },
      }
    );
  }

  describe('draft mutation', () => {
    test('mergeDraft updates the draft and never calls updateTrigger', () => {
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      const { result } = renderDraft();

      expect(result.current.draft.webhook_reply).toBe('before_start');
      expect(result.current.isDirty).toBe(false);

      act(() => {
        result.current.mergeDraft({ webhook_reply: 'after_completion' });
      });

      expect(result.current.draft.webhook_reply).toBe('after_completion');
      // Source trigger is untouched, draft diverges -> dirty.
      expect(result.current.isDirty).toBe(true);
      expect(updateSpy).not.toHaveBeenCalled();
    });

    test('setDraftAuthMethodIds buffers ids and marks dirty without commit', () => {
      const { result } = renderDraft([]);

      expect(result.current.isDirty).toBe(false);

      act(() => {
        result.current.setDraftAuthMethodIds(['auth-1']);
      });

      expect(result.current.draftAuthMethodIds).toEqual(['auth-1']);
      expect(result.current.isDirty).toBe(true);
      expect(commitAuthMethods).not.toHaveBeenCalled();
    });
  });

  describe('commit', () => {
    test('commits a valid draft via updateTrigger exactly once with merged values', async () => {
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      const { result } = renderDraft();

      act(() => {
        result.current.mergeDraft({ webhook_reply: 'after_completion' });
      });

      let outcome: { ok: boolean } | undefined;
      await act(async () => {
        outcome = await result.current.commit();
      });

      expect(outcome).toEqual({ ok: true });
      expect(updateSpy).toHaveBeenCalledTimes(1);
      expect(updateSpy).toHaveBeenCalledWith(
        TRIGGER_ID,
        expect.objectContaining({ webhook_reply: 'after_completion' })
      );
    });

    test('calls commitAuthMethods only when the auth id set changed', async () => {
      const { result, rerender } = renderDraft([]);

      // No auth change -> commitAuthMethods is not called.
      await act(async () => {
        await result.current.commit();
      });
      expect(commitAuthMethods).not.toHaveBeenCalled();

      // Buffer a new id set and commit -> commitAuthMethods fires with the ids.
      act(() => {
        result.current.setDraftAuthMethodIds(['auth-1']);
      });
      await act(async () => {
        await result.current.commit();
      });
      expect(commitAuthMethods).toHaveBeenCalledTimes(1);
      expect(commitAuthMethods).toHaveBeenCalledWith(['auth-1']);

      rerender();
    });

    test('does not call commitAuthMethods when ids are reordered but equal', async () => {
      const { result } = renderDraft(['a', 'b']);

      act(() => {
        result.current.setDraftAuthMethodIds(['b', 'a']);
      });

      await act(async () => {
        await result.current.commit();
      });

      expect(commitAuthMethods).not.toHaveBeenCalled();
    });

    test('returns ok:false and writes no trigger fields when commitAuthMethods fails', async () => {
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      // The auth commit is the only fallible step (a channel request); make it
      // reject to exercise the partial-commit guard.
      commitAuthMethods = vi.fn(() =>
        Promise.reject(new Error('channel down'))
      );
      const { result } = renderDraft([]);

      // Change BOTH a trigger field and the auth set, so a partial commit would
      // be observable if the trigger write ran despite the auth failure.
      act(() => {
        result.current.mergeDraft({ webhook_reply: 'after_completion' });
        result.current.setDraftAuthMethodIds(['auth-1']);
      });

      let outcome: { ok: boolean } | undefined;
      await act(async () => {
        outcome = await result.current.commit();
      });

      // Auth runs first and fails -> the local trigger write never happens.
      expect(outcome).toEqual({ ok: false });
      expect(commitAuthMethods).toHaveBeenCalledTimes(1);
      expect(updateSpy).not.toHaveBeenCalled();
    });

    test('does not persist an invalid draft and surfaces validationError', async () => {
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      const { result } = renderDraft();

      // Webhook triggers require webhook_reply to be a valid enum; an empty
      // string fails the discriminated-union schema.
      act(() => {
        result.current.mergeDraft({
          webhook_reply: '' as unknown as 'before_start',
        });
      });

      expect(result.current.validationError).not.toBeNull();

      let outcome: { ok: boolean } | undefined;
      await act(async () => {
        outcome = await result.current.commit();
      });

      expect(outcome).toEqual({ ok: false });
      expect(updateSpy).not.toHaveBeenCalled();
      expect(commitAuthMethods).not.toHaveBeenCalled();
    });
  });

  describe('async auth-method load (data-loss guard)', () => {
    test('untouched draft tracks initialAuthMethodIds when they load later', () => {
      // Auth methods load async: mount with [] then resolve to ['a'].
      const { result, rerender } = renderDraftWithProp([]);

      expect(result.current.draftAuthMethodIds).toEqual([]);

      act(() => {
        rerender({ ids: ['a'] });
      });

      // Untouched -> the loaded server value is adopted, so a Finish would not
      // wipe the trigger's real auth methods. No commit happens here.
      expect(result.current.draftAuthMethodIds).toEqual(['a']);
      expect(result.current.isDirty).toBe(false);
      expect(commitAuthMethods).not.toHaveBeenCalled();
    });

    test('a user edit is not clobbered by a later initialAuthMethodIds change', () => {
      const { result, rerender } = renderDraftWithProp([]);

      // User takes ownership of the selection.
      act(() => {
        result.current.setDraftAuthMethodIds(['x']);
      });
      expect(result.current.draftAuthMethodIds).toEqual(['x']);

      // A later server load must NOT overwrite the user's edit.
      act(() => {
        rerender({ ids: ['a'] });
      });
      expect(result.current.draftAuthMethodIds).toEqual(['x']);
    });
  });

  describe('concurrent edit (diffs against the open-time baseline)', () => {
    test('commit does not revert a field changed on the live trigger after open', async () => {
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      const { result, rerender } = renderDraftWithTrigger(trigger);

      // User edits one field in the draft.
      act(() => {
        result.current.mergeDraft({ webhook_reply: 'after_completion' });
      });

      // A collaborator toggles `enabled` off on the canvas -> the live trigger
      // prop updates underneath the still-open wizard.
      act(() => {
        rerender({ t: { ...trigger, enabled: false } });
      });

      let outcome: { ok: boolean } | undefined;
      await act(async () => {
        outcome = await result.current.commit();
      });

      // Only the user's field is written; `enabled` (untouched in the draft) is
      // not, so the collaborator's change survives the Finish.
      expect(outcome).toEqual({ ok: true });
      expect(updateSpy).toHaveBeenCalledTimes(1);
      expect(updateSpy).toHaveBeenCalledWith(TRIGGER_ID, {
        webhook_reply: 'after_completion',
      });
    });

    test('an external change alone does not mark the draft dirty', () => {
      const { result, rerender } = renderDraftWithTrigger(trigger);
      expect(result.current.isDirty).toBe(false);

      // Collaborator changes an untouched field on the live trigger; the user
      // has not edited the draft.
      act(() => {
        rerender({ t: { ...trigger, enabled: false } });
      });

      expect(result.current.isDirty).toBe(false);
    });
  });

  describe('reset', () => {
    test('restores draft and auth ids from the source trigger', () => {
      const { result } = renderDraft(['auth-1']);

      act(() => {
        result.current.mergeDraft({ webhook_reply: 'after_completion' });
        result.current.setDraftAuthMethodIds(['auth-1', 'auth-2']);
      });

      expect(result.current.isDirty).toBe(true);

      act(() => {
        result.current.reset();
      });

      expect(result.current.draft.webhook_reply).toBe('before_start');
      expect(result.current.draftAuthMethodIds).toEqual(['auth-1']);
      expect(result.current.isDirty).toBe(false);
    });
  });
});
