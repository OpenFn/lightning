import { useWorkflowState } from '../../../hooks/useWorkflow';
import type { Workflow } from '../../../types/workflow';
import { InspectorLayout } from '../InspectorLayout';

import { humanizeCron } from './cronSchedule';
import { EditFooter } from './EditFooter';
import { ReadOnlyField } from './ReadOnlyField';
import { TriggerTypeBadge } from './TriggerTypeBadge';
import { useCanEditWorkflow } from './useCanEditWorkflow';

interface CronShowPanelProps {
  trigger: Workflow.Trigger;
  onClose: () => void;
  onEdit: () => void;
}

/**
 * Read-only "show / resting" panel for a configured cron trigger.
 *
 * Renders inside {@link InspectorLayout}: the green "Schedule / Cron" badge, a
 * **Frequency** label + a read-only box with the humanized schedule, and a
 * **Cron Input Source** field (the selected step's name, or "Final run state
 * (default)" when unset). The footer holds a single secondary **Edit** action
 * (left) that hands off to the edit wizard.
 *
 * Flat layout (no collapsible sections). All mutation happens through the
 * wizard entered via `onEdit`; this panel never writes to the Y.Doc.
 */
export function CronShowPanel({
  trigger,
  onClose,
  onEdit,
}: CronShowPanelProps) {
  const { canEdit, tooltipMessage } = useCanEditWorkflow();
  const jobs = useWorkflowState(state => state.jobs);

  const cronExpression = trigger.cron_expression ?? '';
  const humanized = humanizeCron(cronExpression);
  const frequency = humanized ?? (cronExpression || 'Invalid schedule');

  const cursorJobId = trigger.cron_cursor_job_id;
  const cursorJobName = cursorJobId
    ? jobs.find(job => job.id === cursorJobId)?.name
    : undefined;
  // Mirror the edit-step select: an unset (or unresolved) cursor reads as the
  // default final-run-state source.
  const inputSource = cursorJobName ?? 'Final run state (default)';

  const footer = (
    <EditFooter
      canEdit={canEdit}
      tooltipMessage={tooltipMessage}
      onEdit={onEdit}
    />
  );

  return (
    <InspectorLayout title="On a schedule" onClose={onClose} footer={footer}>
      <div className="p-6 space-y-6">
        {/* Trigger type badge */}
        <div className="rounded-lg border border-gray-200 bg-white px-3 py-2">
          <TriggerTypeBadge type="cron" />
        </div>

        <ReadOnlyField label="Frequency">{frequency}</ReadOnlyField>
        <ReadOnlyField label="Cron Input Source">{inputSource}</ReadOnlyField>
      </div>
    </InspectorLayout>
  );
}
