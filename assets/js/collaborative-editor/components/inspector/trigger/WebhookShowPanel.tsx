import { useState } from 'react';

import { cn } from '#/utils/cn';

import type { Workflow } from '../../../types/workflow';
import { InspectorLayout } from '../InspectorLayout';

import { EditFooter } from './EditFooter';
import { IMMEDIATELY, ON_COMPLETE } from './ResponseTypeSelect';
import { TriggerTypeBadge } from './TriggerTypeBadge';
import { useCanEditWorkflow } from './useCanEditWorkflow';
import { useWebhookTrigger } from './useWebhookTrigger';
import { WebhookUrlField } from './WebhookUrlField';

/** Backend default webhook response status (success and error) when unset. */
const DEFAULT_STATUS_CODE = 201;

const RESPONSE_DOCS_URL =
  'https://docs.openfn.org/documentation/build/triggers#webhook-trigger-responses';

/**
 * Which Configure-step section the edit wizard should open focused on. Used by
 * the inline "Add authentication" / "Configure default response status" links
 * to deep-link straight into Configure with the relevant section expanded.
 * `undefined` (the plain Edit button) lands on the Choose step.
 */
export type EditFocus = 'authentication' | 'response';

interface WebhookShowPanelProps {
  trigger: Workflow.Trigger;
  onClose: () => void;
  onEdit: (focus?: EditFocus) => void;
}

const readOnlyCodeInputClass =
  'block w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 ' +
  'text-sm text-slate-500';

/**
 * Read-only "show / resting" panel for a configured webhook trigger.
 *
 * Renders inside {@link InspectorLayout} with no footer. Surfaces the webhook
 * URL (with copy), the configured authentication methods (or a placeholder +
 * an "Add Authentication" affordance for editors), a read-only response
 * summary, and a primary **Edit** action that hands off to the edit wizard.
 *
 * All mutation happens through the wizard (entered via `onEdit`); this panel
 * never writes to the Y.Doc.
 */
export function WebhookShowPanel({
  trigger,
  onClose,
  onEdit,
}: WebhookShowPanelProps) {
  const { canEdit, tooltipMessage } = useCanEditWorkflow();
  const {
    webhookUrl,
    copyText,
    copyToClipboard,
    triggerAuthMethods,
    loadingAuthMethods,
  } = useWebhookTrigger(trigger);

  const [authExpanded, setAuthExpanded] = useState(false);
  const [responseExpanded, setResponseExpanded] = useState(false);

  const authCount = triggerAuthMethods.length;
  const authCountLabel = loadingAuthMethods
    ? 'loading…'
    : authCount === 0
      ? 'none configured'
      : `${authCount} configured`;

  const responseConfig = trigger.webhook_response_config;
  const isAfterCompletion = trigger.webhook_reply === 'after_completion';
  const responseType = isAfterCompletion ? ON_COMPLETE : IMMEDIATELY;
  const successCode = responseConfig?.success_code ?? DEFAULT_STATUS_CODE;
  const errorCode = responseConfig?.error_code ?? DEFAULT_STATUS_CODE;
  const hasResponseConfig =
    responseConfig != null &&
    (responseConfig.success_code != null || responseConfig.error_code != null);

  const footer = (
    <EditFooter
      canEdit={canEdit}
      tooltipMessage={tooltipMessage}
      onEdit={() => onEdit()}
    />
  );

  return (
    <InspectorLayout title="On webhook call" onClose={onClose} footer={footer}>
      <div className="p-6 space-y-6">
        {/* Trigger type badge */}
        <div>
          <TriggerTypeBadge />
        </div>

        {/* Webhook URL */}
        <WebhookUrlField
          url={webhookUrl}
          copyText={copyText}
          onCopy={url => void copyToClipboard(url)}
        />

        {/* Authentication */}
        <div>
          <button
            type="button"
            onClick={() => setAuthExpanded(v => !v)}
            className="flex w-full items-center gap-1.5 text-sm font-medium
              text-slate-800 focus:outline-none"
          >
            <span
              className={cn(
                'h-3.5 w-3.5 transition-transform',
                authExpanded
                  ? 'hero-chevron-down-mini'
                  : 'hero-chevron-right-mini'
              )}
            />
            Authentication
            <span className="text-xs font-normal text-slate-400">
              ({authCountLabel})
            </span>
          </button>

          {authExpanded && (
            <div className="mt-2">
              {loadingAuthMethods ? (
                <div className="flex items-center gap-1 text-xs text-slate-600">
                  <span className="hero-arrow-path size-4 animate-spin" />
                  loading authentication methods
                </div>
              ) : triggerAuthMethods.length > 0 ? (
                <div className="space-y-1">
                  {triggerAuthMethods.map(method => (
                    <div
                      key={method.id}
                      className="flex items-center gap-2 text-xs"
                    >
                      <span className="hero-shield-check-micro h-4 w-4 text-green-600" />
                      <span className="font-medium text-slate-700">
                        {method.name}
                      </span>
                      <span className="text-slate-400">
                        ({method.auth_type === 'api' ? 'API Key' : 'Basic Auth'}
                        )
                      </span>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-xs text-slate-500">
                  No authentication configured.
                  {canEdit && (
                    <>
                      {' '}
                      <button
                        type="button"
                        onClick={() => onEdit('authentication')}
                        className="link text-xs font-medium no-underline"
                      >
                        Add authentication
                      </button>
                    </>
                  )}
                </p>
              )}
            </div>
          )}
        </div>

        {/* Response */}
        <div>
          <button
            type="button"
            onClick={() => setResponseExpanded(v => !v)}
            className="flex w-full items-center gap-1.5 text-sm font-medium
              text-slate-800 focus:outline-none"
          >
            <span
              className={cn(
                'h-3.5 w-3.5 transition-transform',
                responseExpanded
                  ? 'hero-chevron-down-mini'
                  : 'hero-chevron-right-mini'
              )}
            />
            Response
          </button>

          {responseExpanded && (
            <div className="mt-2 space-y-3">
              <p className="text-xs leading-5 text-slate-500">
                {responseType.shortDescription}
                {!isAfterCompletion && (
                  <>
                    {' '}
                    <a
                      href={RESPONSE_DOCS_URL}
                      target="_blank"
                      rel="noreferrer"
                      className="link text-xs"
                    >
                      learn more
                    </a>
                  </>
                )}
                {isAfterCompletion && !hasResponseConfig && canEdit && (
                  <>
                    {' '}
                    <button
                      type="button"
                      onClick={() => onEdit('response')}
                      className="link text-xs font-medium no-underline"
                    >
                      Configure default response status
                    </button>
                  </>
                )}
              </p>

              {isAfterCompletion && hasResponseConfig && (
                <div className="space-y-2">
                  <div className="flex items-start gap-3">
                    <div className="flex-1 space-y-1">
                      <span className="block text-xs font-medium text-slate-600">
                        Default success status
                      </span>
                      <input
                        type="text"
                        disabled
                        value={successCode}
                        className={readOnlyCodeInputClass}
                      />
                    </div>
                    <div className="flex-1 space-y-1">
                      <span className="block text-xs font-medium text-slate-600">
                        Default error status
                      </span>
                      <input
                        type="text"
                        disabled
                        value={errorCode}
                        className={readOnlyCodeInputClass}
                      />
                    </div>
                  </div>
                  <p className="text-xs leading-5 text-slate-500">
                    These are defaults — you can override the response status
                    and body in your job code.{' '}
                    <a
                      href={RESPONSE_DOCS_URL}
                      target="_blank"
                      rel="noreferrer"
                      className="link text-xs"
                    >
                      Learn how
                    </a>
                    .
                  </p>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </InspectorLayout>
  );
}
