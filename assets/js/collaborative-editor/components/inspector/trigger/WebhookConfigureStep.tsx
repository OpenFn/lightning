import { useMemo, useState } from 'react';

import { cn } from '#/utils/cn';

import {
  usePermissions,
  useSessionContext,
} from '../../../hooks/useSessionContext';
import type { WebhookAuthMethod } from '../../../types/sessionContext';
import type { Workflow } from '../../../types/workflow';
import { Button } from '../../Button';
import { InspectorFooter } from '../InspectorFooter';
import { InspectorLayout } from '../InspectorLayout';
import { WebhookAuthMethodModal } from '../WebhookAuthMethodModal';

import { ResponseTypeSelect } from './ResponseTypeSelect';
import { WizardBreadcrumb } from './WizardBreadcrumb';

const codeInputClass = cn(
  'block w-full rounded-lg border border-gray-200 bg-white px-3 py-2',
  'text-sm text-slate-700',
  'focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500'
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
  onClose,
  onCancel,
  onBack,
  onFinish,
}: WebhookConfigureStepProps) {
  const permissions = usePermissions();
  const { webhookAuthMethods, project } = useSessionContext();
  const canWriteAuth = Boolean(permissions?.can_write_webhook_auth_method);

  const [showAuthModal, setShowAuthModal] = useState(false);
  // Both progressive-disclosure sections start collapsed, matching Figma 1.2.0.
  const [authExpanded, setAuthExpanded] = useState(false);
  const [responseExpanded, setResponseExpanded] = useState(false);

  const config = draft.webhook_response_config ?? null;
  const isAfterCompletion = draft.webhook_reply === 'after_completion';

  const projectAuthMethods = useMemo<WebhookAuthMethod[]>(
    () => webhookAuthMethods ?? [],
    [webhookAuthMethods]
  );

  // Resolve buffered ids against the project methods for display + the modal.
  const selectedMethods = useMemo<WebhookAuthMethod[]>(
    () => projectAuthMethods.filter(m => draftAuthMethodIds.includes(m.id)),
    [projectAuthMethods, draftAuthMethodIds]
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
              {selectedMethods.length > 0 ? (
                <div className="space-y-1">
                  {selectedMethods.map(method => (
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
                <p className="text-xs text-slate-500 italic">
                  No auth configured
                </p>
              )}

              <button
                type="button"
                onClick={() => setShowAuthModal(true)}
                disabled={!canWriteAuth}
                className={cn(
                  'link text-sm font-semibold inline-flex items-center gap-1',
                  'no-underline',
                  !canWriteAuth && 'text-gray-400 cursor-not-allowed'
                )}
              >
                <span className="hero-plus-micro h-4 w-4" />
                Manage authentication
              </button>
            </div>
          )}
        </div>

        {/* Response Options */}
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
      </div>

      {/* Webhook Auth Method Modal — buffers selection into the draft; the
          channel request fires on Finish via the draft hook, not here. */}
      {showAuthModal && (
        <WebhookAuthMethodModal
          trigger={
            {
              ...draft,
              webhook_auth_methods: selectedMethods,
            } as unknown as Workflow.Trigger
          }
          projectAuthMethods={projectAuthMethods}
          projectId={project?.id ?? ''}
          onClose={() => setShowAuthModal(false)}
          onSave={ids => {
            // Buffer the selection into the draft; the channel commit happens on
            // Finish via the draft hook, not here.
            setDraftAuthMethodIds(ids);
            setShowAuthModal(false);
            return Promise.resolve();
          }}
        />
      )}
    </InspectorLayout>
  );
}
