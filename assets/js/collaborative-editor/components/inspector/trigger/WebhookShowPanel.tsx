import { Tooltip } from '../../../../components/Tooltip';
import { usePermissions } from '../../../hooks/useSessionContext';
import { useWorkflowReadOnly } from '../../../hooks/useWorkflow';
import type { Workflow } from '../../../types/workflow';
import { Button } from '../../Button';
import { InspectorLayout } from '../InspectorLayout';

import { TriggerTypeBadge } from './TriggerTypeBadge';
import { useWebhookTrigger } from './useWebhookTrigger';
import { WebhookUrlField } from './WebhookUrlField';

interface WebhookShowPanelProps {
  trigger: Workflow.Trigger;
  onClose: () => void;
  onEdit: () => void;
}

/**
 * Read-only "show / resting" panel for a configured webhook trigger (#4797).
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
  const permissions = usePermissions();
  const { isReadOnly, tooltipMessage } = useWorkflowReadOnly();
  const {
    webhookUrl,
    copyText,
    copyToClipboard,
    triggerAuthMethods,
    loadingAuthMethods,
  } = useWebhookTrigger(trigger);

  const canEdit = Boolean(permissions?.can_edit_workflow) && !isReadOnly;

  const responseConfig = trigger.webhook_response_config;
  const isAfterCompletion = trigger.webhook_reply === 'after_completion';

  return (
    <InspectorLayout title="On webhook call" onClose={onClose}>
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
        <div className="space-y-2 pt-4 border-t border-slate-200">
          <h4 className="text-sm font-medium text-slate-800">Authentication</h4>

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
                    ({method.auth_type === 'api' ? 'API Key' : 'Basic Auth'})
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <div className="space-y-2">
              <p className="text-xs text-slate-500 italic">
                No auth configured
              </p>
              {canEdit && (
                <Button variant="secondary" onClick={onEdit}>
                  Add Authentication
                </Button>
              )}
            </div>
          )}
        </div>

        {/* Response summary */}
        <div className="space-y-1 pt-4 border-t border-slate-200">
          <p className="text-sm text-slate-700">
            <span className="font-medium text-slate-800">Response:</span>{' '}
            {isAfterCompletion ? 'On complete' : 'Immediately'}
          </p>
          {isAfterCompletion && responseConfig?.success_code != null && (
            <p className="text-xs text-slate-500">
              Success code: {responseConfig.success_code}
            </p>
          )}
          {isAfterCompletion && responseConfig?.error_code != null && (
            <p className="text-xs text-slate-500">
              Error code: {responseConfig.error_code}
            </p>
          )}
        </div>

        {/* Edit action */}
        <div className="pt-2">
          <Tooltip content={canEdit ? 'Edit trigger' : tooltipMessage}>
            <span className="inline-block">
              <Button
                variant="primary"
                onClick={onEdit}
                disabled={!canEdit}
                aria-label="Edit trigger"
              >
                Edit
              </Button>
            </span>
          </Tooltip>
        </div>
      </div>
    </InspectorLayout>
  );
}
