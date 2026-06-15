import type { Workflow } from '../../../types/workflow';
import { InspectorLayout } from '../InspectorLayout';

import { EditFooter } from './EditFooter';
import { ReadOnlyField } from './ReadOnlyField';
import { TriggerTypeBadge } from './TriggerTypeBadge';
import { useCanEditWorkflow } from './useCanEditWorkflow';

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
  const { canEdit, tooltipMessage } = useCanEditWorkflow();

  const config = trigger.kafka_configuration;

  const hosts = config?.hosts_string || '—';
  const topics = config?.topics_string || '—';
  const ssl = config?.ssl ? 'Enabled' : 'Disabled';
  const authentication = config?.sasl
    ? (SASL_LABELS[config.sasl] ?? config.sasl)
    : 'None';

  const footer = (
    <EditFooter
      canEdit={canEdit}
      tooltipMessage={tooltipMessage}
      onEdit={onEdit}
    />
  );

  return (
    <InspectorLayout title="Kafka" onClose={onClose} footer={footer}>
      <div className="p-6 space-y-6">
        {/* Trigger type badge */}
        <div className="rounded-lg border border-gray-200 bg-white px-3 py-2">
          <TriggerTypeBadge type="kafka" />
        </div>

        <ReadOnlyField label="Hosts">{hosts}</ReadOnlyField>
        <ReadOnlyField label="Topics">{topics}</ReadOnlyField>
        <ReadOnlyField label="SSL">{ssl}</ReadOnlyField>
        <ReadOnlyField label="Authentication">{authentication}</ReadOnlyField>
      </div>
    </InspectorLayout>
  );
}
