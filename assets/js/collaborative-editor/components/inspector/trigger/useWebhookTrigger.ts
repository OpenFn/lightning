import { useCallback, useEffect } from 'react';

import { useCopyToClipboard } from '#/collaborative-editor/hooks/useCopyToClipboard';

import { channelRequest } from '../../../hooks/useChannel';
import { useSession } from '../../../hooks/useSession';
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
  /** The webhook ingest URL for this trigger (`<origin>/i/<trigger.id>`). */
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
 * Shared webhook-trigger logic, extracted from `TriggerForm` so the read-only
 * show panel and the edit wizard's Configure step can rely on a single source
 * of truth rather than duplicating the webhook field logic.
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
  const channel = provider?.channel;

  // Get active trigger auth methods from workflow store
  const activeTriggerAuthMethods = useWorkflowState(
    state => state.activeTriggerAuthMethods
  );

  // Request auth methods when the trigger changes
  useEffect(() => {
    if (trigger.id) {
      void requestTriggerAuthMethods(trigger.id);
    }
  }, [trigger.id, requestTriggerAuthMethods]);

  // Derive auth methods / loading state for this trigger
  const triggerAuthMethods =
    activeTriggerAuthMethods?.trigger_id === trigger.id
      ? (activeTriggerAuthMethods.webhook_auth_methods as WebhookAuthMethod[])
      : [];
  const loadingAuthMethods =
    activeTriggerAuthMethods === null ||
    activeTriggerAuthMethods.trigger_id !== trigger.id;

  // Generate webhook URL based on trigger ID
  const webhookUrl = new URL(
    `/i/${trigger.id}`,
    window.location.origin
  ).toString();

  // Persist the given auth-method id set via the channel.
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
