import { useEffect, useMemo, useState } from 'react';

import { cn } from '#/utils/cn';

import { useLiveViewActions } from '../../../contexts/LiveViewActionsContext';
import {
  usePermissions,
  useSessionContext,
} from '../../../hooks/useSessionContext';
import { useWorkflowReadOnly } from '../../../hooks/useWorkflow';
import type { WebhookAuthMethod } from '../../../types/sessionContext';
import type { Workflow } from '../../../types/workflow';
import { Button } from '../../Button';
import { InspectorFooter } from '../InspectorFooter';
import { InspectorLayout } from '../InspectorLayout';

import { ResponseTypeSelect } from './ResponseTypeSelect';
import { WebhookAuthMethodSelect } from './WebhookAuthMethodSelect';
import { WizardBreadcrumb } from './WizardBreadcrumb';

const codeInputClass = cn(
  'block w-full rounded-lg border border-gray-200 bg-white px-3 py-2',
  'text-sm text-slate-700',
  'focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500',
  'disabled:cursor-not-allowed disabled:opacity-50'
);

type ResponseConfig = {
  success_code: number | null;
  error_code: number | null;
} | null;

interface WebhookConfigureStepProps {
  /** The local trigger draft. */
  draft: Workflow.Trigger;
  /** Shallow-merge updates into the draft. */
  mergeDraft: (updates: Partial<Workflow.Trigger>) => void;
  /** The local, uncommitted auth-method id set. */
  draftAuthMethodIds: string[];
  /** Replace the draft auth-method id set (buffered; committed on Finish). */
  setDraftAuthMethodIds: (ids: string[]) => void;
  /** Validation error to surface near the footer after a failed Finish. */
  validationError: string | null;
  /** Which disclosure to open expanded on mount (deep-link from show panel). */
  initialExpand?: 'authentication' | 'response' | undefined;
  /** Close the inspector entirely. */
  onClose: () => void;
  /** Discard the draft and leave the wizard (Cancel). */
  onCancel: () => void;
  /** Return to the Choose step (Back / header arrow). */
  onBack: () => void;
  /** Validate + commit the draft (Finish). */
  onFinish: () => void;
}

function hasResponseConfig(config: ResponseConfig): boolean {
  if (!config) return false;
  return config.success_code != null || config.error_code != null;
}

/**
 * The wizard's "Configure" step. Binds entirely to the local DRAFT — every
 * change calls `mergeDraft` / `setDraftAuthMethodIds`; nothing is persisted
 * until Finish. Mirrors the Response Type, Authentication, and Response Options
 * behaviour of the legacy `TriggerForm` webhook branch.
 */
export function WebhookConfigureStep({
  draft,
  mergeDraft,
  draftAuthMethodIds,
  setDraftAuthMethodIds,
  validationError,
  initialExpand,
  onClose,
  onCancel,
  onBack,
  onFinish,
}: WebhookConfigureStepProps) {
  const permissions = usePermissions();
  const { webhookAuthMethods } = useSessionContext();
  const { pushEvent } = useLiveViewActions();
  const { isReadOnly } = useWorkflowReadOnly();
  const canWriteAuth = Boolean(permissions?.can_write_webhook_auth_method);

  // Both progressive-disclosure sections start collapsed (matching Figma 1.2.0)
  // unless the user deep-linked into one via a show-panel link.
  const [authExpanded, setAuthExpanded] = useState(
    initialExpand === 'authentication'
  );
  const [responseExpanded, setResponseExpanded] = useState(
    initialExpand === 'response'
  );

  // The create-auth-method modal is rendered server-side by the Collaborate
  // LiveView. Its Cancel/close buttons dispatch a `close_webhook_auth_modal`
  // DOM event to the React root; we must relay that to the server so it clears
  // `show_webhook_auth_modal`. (Save already closes itself server-side.)
  useEffect(() => {
    const handleModalClose = () => {
      pushEvent('close_webhook_auth_modal_complete', {});
    };

    const element = document.getElementById('collaborative-editor-react');
    element?.addEventListener('close_webhook_auth_modal', handleModalClose);

    return () => {
      element?.removeEventListener(
        'close_webhook_auth_modal',
        handleModalClose
      );
    };
  }, [pushEvent]);

  const config = draft.webhook_response_config ?? null;
  const isAfterCompletion = draft.webhook_reply === 'after_completion';

  const projectAuthMethods = useMemo<WebhookAuthMethod[]>(
    () => webhookAuthMethods ?? [],
    [webhookAuthMethods]
  );

  const baseConfig = config ?? { success_code: null, error_code: null };

  const footer = (
    <div className="space-y-2">
      {validationError && (
        <p className="text-xs text-red-600">{validationError}</p>
      )}
      <InspectorFooter
        leftButtons={
          <Button variant="ghost" onClick={onCancel}>
            Cancel
          </Button>
        }
        rightButtons={
          <Button variant="primary" onClick={onFinish}>
            <span className="inline-flex items-center gap-1.5">
              Finish
              <span className="hero-arrow-right-micro h-4 w-4" />
            </span>
          </Button>
        }
      />
    </div>
  );

  return (
    <InspectorLayout title="On webhook call" onClose={onClose} footer={footer}>
      <div className="space-y-6 p-6">
        <WizardBreadcrumb
          step="configure"
          onNavigate={target => {
            if (target === 'choose') onBack();
          }}
        />

        {/* Response Type */}
        <div className="space-y-1">
          <ResponseTypeSelect
            value={draft.webhook_reply ?? 'before_start'}
            disabled={isReadOnly}
            onChange={value => {
              mergeDraft({
                webhook_reply: value,
                ...(value === 'before_start'
                  ? { webhook_response_config: null }
                  : {}),
              });
            }}
          />
          {isAfterCompletion && hasResponseConfig(config) && (
            <p className="text-xs text-amber-600">
              Switching to async will clear your response configuration.
            </p>
          )}
        </div>

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
          </button>

          {authExpanded && (
            <div className="mt-2 space-y-2">
              <p className="text-xs text-slate-500">
                Require requests to this webhook to use specific authentication
                protocols.
              </p>
              <WebhookAuthMethodSelect
                methods={projectAuthMethods}
                selectedIds={draftAuthMethodIds}
                onChange={setDraftAuthMethodIds}
                onCreateNew={() => pushEvent('open_webhook_auth_modal', {})}
                canCreate={canWriteAuth}
                disabled={isReadOnly}
              />
            </div>
          )}
        </div>

        {/* Response Options — a custom status/body is only possible when the
            webhook responds on completion. */}
        {isAfterCompletion && (
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
              Response Options
            </button>

            {responseExpanded && (
              <div className="mt-3 flex items-start gap-3">
                <div className="flex-1 space-y-1">
                  <label
                    htmlFor="webhook-success-code"
                    className="block text-xs font-medium text-slate-600"
                  >
                    Success Code
                  </label>
                  <input
                    id="webhook-success-code"
                    type="number"
                    inputMode="numeric"
                    placeholder="201"
                    disabled={isReadOnly}
                    value={config?.success_code ?? ''}
                    onChange={e => {
                      const raw = e.target.value;
                      mergeDraft({
                        webhook_response_config: {
                          ...baseConfig,
                          success_code: raw === '' ? null : parseInt(raw, 10),
                        },
                      });
                    }}
                    className={codeInputClass}
                  />
                </div>
                <div className="flex-1 space-y-1">
                  <label
                    htmlFor="webhook-error-code"
                    className="block text-xs font-medium text-slate-600"
                  >
                    Error Code
                  </label>
                  <input
                    id="webhook-error-code"
                    type="number"
                    inputMode="numeric"
                    placeholder="201"
                    disabled={isReadOnly}
                    value={config?.error_code ?? ''}
                    onChange={e => {
                      const raw = e.target.value;
                      mergeDraft({
                        webhook_response_config: {
                          ...baseConfig,
                          error_code: raw === '' ? null : parseInt(raw, 10),
                        },
                      });
                    }}
                    className={codeInputClass}
                  />
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </InspectorLayout>
  );
}
