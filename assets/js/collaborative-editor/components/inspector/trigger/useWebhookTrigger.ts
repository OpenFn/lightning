import { useCallback, useEffect } from 'react';

import { useCopyToClipboard } from '#/collaborative-editor/hooks/useCopyToClipboard';
import { isValidCustomPath } from '#/collaborative-editor/types/trigger';

import { channelRequest } from '../../../hooks/useChannel';
import { useSession } from '../../../hooks/useSession';
import { useProject } from '../../../hooks/useSessionContext';
import {
  useWorkflowActions,
  useWorkflowState,
} from '../../../hooks/useWorkflow';
import { notifications } from '../../../lib/notifications';
import type { WebhookAuthMethod } from '../../../types/sessionContext';
import type { Workflow } from '../../../types/workflow';

/**
 * Return shape of the {@link useWebhookTrigger} hook.
 */
export interface UseWebhookTriggerResult {
  /**
   * The webhook ingest URL for this trigger: `<origin>/i/<project.id>/<path>`
   * when it has a custom path, `<origin>/i/<trigger.id>` otherwise.
   */
  webhookUrl: string;
  /** Display text for the copy button ('' | 'Copied!' | 'Failed'). */
  copyText: string;
  /** Copies the given text to the clipboard with feedback. */
  copyToClipboard: (text: string) => Promise<void>;
  /** Auth methods currently associated with this trigger (empty while loading). */
  triggerAuthMethods: WebhookAuthMethod[];
  /** True while the trigger's auth methods are being (re)loaded. */
  loadingAuthMethods: boolean;
  /**
   * Persists the given auth-method id set for this trigger via the
   * `update_trigger_auth_methods` channel request. Surfaces success/failure
   * notifications and rethrows on failure.
   */
  commitAuthMethods: (ids: string[]) => Promise<void>;
}

/**
 * Shared webhook-trigger logic so the read-only show panel and the edit
 * wizard's Configure step rely on a single source of truth rather than
 * duplicating the webhook field logic.
 *
 * Responsibilities:
 * - Derive the webhook ingest URL and expose copy-to-clipboard helpers.
 * - Load the trigger's webhook auth methods into the workflow store on mount /
 *   when the trigger id changes, and expose them plus a loading flag.
 * - Provide `commitAuthMethods` which issues the `update_trigger_auth_methods`
 *   channel request. This is intentionally NOT wired to any modal `onSave`; the
 *   wizard buffers selections in a draft and only commits on Finish.
 *
 * @param trigger The trigger being inspected.
 */
export function useWebhookTrigger(
  trigger: Workflow.Trigger
): UseWebhookTriggerResult {
  const { requestTriggerAuthMethods } = useWorkflowActions();
  const { copyText, copyToClipboard } = useCopyToClipboard();
  const { provider } = useSession();
  const project = useProject();
  const channel = provider?.channel;

  const activeTriggerAuthMethods = useWorkflowState(
    state => state.activeTriggerAuthMethods
  );

  // Request auth methods when the trigger changes. Only webhook triggers have
  // associated auth methods; firing this for cron triggers would hit the
  // server's `request_trigger_auth_methods` path for a non-webhook trigger and
  // produce NoResults noise. This hook is called unconditionally by the unified
  // wizard (React hook rules), so we guard the effect body by type instead.
  useEffect(() => {
    if (trigger.type === 'webhook' && trigger.id) {
      void requestTriggerAuthMethods(trigger.id);
    }
  }, [trigger.type, trigger.id, requestTriggerAuthMethods]);

  const triggerAuthMethods =
    activeTriggerAuthMethods?.trigger_id === trigger.id
      ? (activeTriggerAuthMethods.webhook_auth_methods as WebhookAuthMethod[])
      : [];
  const loadingAuthMethods =
    activeTriggerAuthMethods === null ||
    activeTriggerAuthMethods.trigger_id !== trigger.id;

  const customPath =
    trigger.type === 'webhook' ? (trigger.custom_path ?? null) : null;

  // A refused path is not this trigger's. It stays in the Y.Doc, and a duplicate
  // resolves to whichever workflow legitimately owns it.
  const rejected = Boolean(trigger.errors?.['custom_path']?.length);

  // Only a path the lookup can match. A legacy one holding a slash is stored
  // verbatim but is not addressable, so the generated URL is the one that works.
  const addressable =
    !rejected && customPath !== null && isValidCustomPath(customPath);

  // Not encoded: the plug runs before the router and compares raw segments.
  const path =
    addressable && project?.id
      ? `/i/${project.id}/${customPath}`
      : `/i/${trigger.id}`;

  const webhookUrl = new URL(path, window.location.origin).toString();

  const commitAuthMethods = useCallback(
    async (ids: string[]) => {
      if (!channel || !trigger.id) {
        throw new Error(
          'Cannot save: channel not connected or trigger not saved'
        );
      }

      try {
        await channelRequest(channel, 'update_trigger_auth_methods', {
          trigger_id: trigger.id,
          auth_method_ids: ids,
        });

        notifications.info({
          title: 'Authentication updated',
          description: 'Webhook authentication methods have been updated',
        });
      } catch (error) {
        const errorMessage =
          error instanceof Error ? error.message : 'An error occurred';

        notifications.alert({
          title: 'Failed to update',
          description: errorMessage,
        });

        throw error;
      }
    },
    [channel, trigger.id]
  );

  return {
    webhookUrl,
    copyText,
    copyToClipboard,
    triggerAuthMethods,
    loadingAuthMethods,
    commitAuthMethods,
  };
}
