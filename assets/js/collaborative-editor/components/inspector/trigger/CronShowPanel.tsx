import { Tooltip } from '../../../../components/Tooltip';
import { usePermissions } from '../../../hooks/useSessionContext';
import {
  useWorkflowReadOnly,
  useWorkflowState,
} from '../../../hooks/useWorkflow';
import type { Workflow } from '../../../types/workflow';
import { Button } from '../../Button';
import { InspectorFooter } from '../InspectorFooter';
import { InspectorLayout } from '../InspectorLayout';

import { humanizeCron } from './cronSchedule';
import { TriggerTypeBadge } from './TriggerTypeBadge';

interface CronShowPanelProps {
  trigger: Workflow.Trigger;
  onClose: () => void;
  onEdit: () => void;
}

/**
 * Read-only "show / resting" panel for a configured cron trigger (#4787).
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
  const permissions = usePermissions();
  const { isReadOnly, tooltipMessage } = useWorkflowReadOnly();
  const jobs = useWorkflowState(state => state.jobs);

  const canEdit = Boolean(permissions?.can_edit_workflow) && !isReadOnly;

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
    <InspectorLayout title="On a Schedule" onClose={onClose} footer={footer}>
      <div className="p-6 space-y-6">
        {/* Trigger type badge */}
        <div className="rounded-lg border border-gray-200 bg-white px-3 py-2">
          <TriggerTypeBadge type="cron" />
        </div>

        {/* Frequency */}
        <div className="space-y-2">
          <span className="block text-sm font-medium text-slate-900">
            Frequency
          </span>
          <div
            className="rounded-lg border border-gray-200 bg-white px-3 py-2
              text-sm text-slate-500"
          >
            {frequency}
          </div>
        </div>

        {/* Cron Input Source */}
        <div className="space-y-2">
          <span className="block text-sm font-medium text-slate-900">
            Cron Input Source
          </span>
          <div
            className="rounded-lg border border-gray-200 bg-white px-3 py-2
              text-sm text-slate-500"
          >
            {inputSource}
          </div>
        </div>
      </div>
    </InspectorLayout>
  );
}
