import { useCallback, useEffect, useState } from 'react';

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

/** One address this trigger answers on. */
export interface WebhookEndpoint {
  /** Full ingest URL. */
  url: string;
  /** What it is called in the list. */
  label: string;
  /** The permanent `/i/<trigger-id>` URL, which every trigger always has. */
  generated: boolean;
  /**
   * False while a path is being typed and is not yet something the lookup can
   * match. The row stays visible so it does not vanish mid-edit, but it is not
   * offered for copying.
   */
  usable?: boolean;
}

/**
 * The URLs a webhook trigger answers on, default first.
 *
 * Shared by the show panel, which builds them from the saved trigger, and the
 * Configure step, which builds them from the draft so the list shows the URL
 * taking shape as you type.
 *
 * Only a path the lookup can match earns a row: a legacy one holding a slash is
 * stored verbatim but is not addressable, and the default URL is what works. The
 * path is not encoded, because the plug runs before the router and compares raw
 * segments.
 */
export function buildWebhookEndpoints({
  triggerId,
  projectId,
  customPath,
  rejected = false,
}: {
  triggerId: string;
  projectId: string | null;
  customPath: string | null;
  /**
   * The server refused this path, so it is not this trigger's. A duplicate
   * resolves to whichever workflow owns it, so the row shows but does not copy.
   */
  rejected?: boolean;
}): WebhookEndpoint[] {
  const addressable =
    customPath !== null && customPath !== '' && isValidCustomPath(customPath);

  // Default first: it never changes, and it puts the custom row next to the
  // field that edits it.
  return [
    {
      url: new URL(`/i/${triggerId}`, window.location.origin).toString(),
      label: 'Default',
      generated: true,
    },
    ...(addressable && projectId
      ? [
          {
            url: new URL(
              `/i/${projectId}/${customPath}`,
              window.location.origin
            ).toString(),
            label: 'Custom',
            generated: false,
            usable: !rejected,
          },
        ]
      : []),
  ];
}

/**
 * Return shape of the {@link useWebhookTrigger} hook.
 */
export interface UseWebhookTriggerResult {
  /**
   * Every URL this trigger answers on, default first. Naming a webhook adds an
   * address, it never replaces the default, so that one is always here.
   */
  endpoints: WebhookEndpoint[];
  /** Display text for the copy button ('' | 'Copied!' | 'Failed'). */
  copyText: string;
  /** The URL the last copy applied to, so only that row shows feedback. */
  copiedUrl: string | null;
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
  const { copyText, copyToClipboard: copy } = useCopyToClipboard();
  const [copiedUrl, setCopiedUrl] = useState<string | null>(null);

  const copyToClipboard = useCallback(
    async (text: string) => {
      setCopiedUrl(text);
      await copy(text);
    },
    [copy]
  );
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

  const endpoints = buildWebhookEndpoints({
    triggerId: trigger.id,
    projectId: project?.id ?? null,
    customPath,
    rejected: Boolean(trigger.errors?.['custom_path']?.length),
  });

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
    endpoints,
    copyText,
    copiedUrl,
    copyToClipboard,
    triggerAuthMethods,
    loadingAuthMethods,
    commitAuthMethods,
  };
}
