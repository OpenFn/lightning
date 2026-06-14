import { Tooltip } from '../../../../components/Tooltip';
import { usePermissions } from '../../../hooks/useSessionContext';
import { useWorkflowReadOnly } from '../../../hooks/useWorkflow';
import type { Workflow } from '../../../types/workflow';
import { Button } from '../../Button';
import { InspectorFooter } from '../InspectorFooter';
import { InspectorLayout } from '../InspectorLayout';

import { TriggerTypeBadge } from './TriggerTypeBadge';

interface KafkaShowPanelProps {
  trigger: Workflow.Trigger;
  onClose: () => void;
  onEdit: () => void;
}

const SASL_LABELS: Record<string, string> = {
  plain: 'PLAIN',
  scram_sha_256: 'SCRAM-SHA-256',
  scram_sha_512: 'SCRAM-SHA-512',
};

/**
 * Read-only "show / resting" panel for a configured kafka trigger (#4787).
 *
 * Renders inside {@link InspectorLayout}: the green "Kafka" badge, then a flat
 * set of read-only summary fields (Hosts, Topics, SSL on/off, Authentication =
 * SASL mechanism or "None"). The footer holds a single secondary **Edit**
 * action (left) that hands off to the edit wizard.
 *
 * Flat layout (no collapsible sections). All mutation happens through the
 * wizard entered via `onEdit`; this panel never writes to the Y.Doc.
 */
export function KafkaShowPanel({
  trigger,
  onClose,
  onEdit,
}: KafkaShowPanelProps) {
  const permissions = usePermissions();
  const { isReadOnly, tooltipMessage } = useWorkflowReadOnly();

  const canEdit = Boolean(permissions?.can_edit_workflow) && !isReadOnly;

  const config = trigger.kafka_configuration;

  const hosts = config?.hosts_string || '—';
  const topics = config?.topics_string || '—';
  const ssl = config?.ssl ? 'Enabled' : 'Disabled';
  const authentication = config?.sasl
    ? (SASL_LABELS[config.sasl] ?? config.sasl)
    : 'None';

  const footer = (
    <InspectorFooter
      leftButtons={
        <Tooltip content={canEdit ? 'Edit trigger' : tooltipMessage}>
          <span className="inline-block">
            <Button
              variant="secondary"
              onClick={() => onEdit()}
              disabled={!canEdit}
              aria-label="Edit trigger"
            >
              Edit
            </Button>
          </span>
        </Tooltip>
      }
    />
  );

  return (
    <InspectorLayout title="Kafka" onClose={onClose} footer={footer}>
      <div className="p-6 space-y-6">
        {/* Trigger type badge */}
        <div className="rounded-lg border border-gray-200 bg-white px-3 py-2">
          <TriggerTypeBadge type="kafka" />
        </div>

        {/* Hosts */}
        <div className="space-y-2">
          <span className="block text-sm font-medium text-slate-900">
            Hosts
          </span>
          <div
            className="rounded-lg border border-gray-200 bg-white px-3 py-2
              text-sm text-slate-500"
          >
            {hosts}
          </div>
        </div>

        {/* Topics */}
        <div className="space-y-2">
          <span className="block text-sm font-medium text-slate-900">
            Topics
          </span>
          <div
            className="rounded-lg border border-gray-200 bg-white px-3 py-2
              text-sm text-slate-500"
          >
            {topics}
          </div>
        </div>

        {/* SSL */}
        <div className="space-y-2">
          <span className="block text-sm font-medium text-slate-900">SSL</span>
          <div
            className="rounded-lg border border-gray-200 bg-white px-3 py-2
              text-sm text-slate-500"
          >
            {ssl}
          </div>
        </div>

        {/* Authentication */}
        <div className="space-y-2">
          <span className="block text-sm font-medium text-slate-900">
            Authentication
          </span>
          <div
            className="rounded-lg border border-gray-200 bg-white px-3 py-2
              text-sm text-slate-500"
          >
            {authentication}
          </div>
        </div>
      </div>
    </InspectorLayout>
  );
}
