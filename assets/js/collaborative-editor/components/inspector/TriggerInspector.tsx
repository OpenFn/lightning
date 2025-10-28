import { usePermissions } from "../../hooks/useSessionContext";
import { useCanRun } from "../../hooks/useWorkflow";
import type { Workflow } from "../../types/workflow";
import { Button } from "../Button";
import { Tooltip } from "../Tooltip";

import { InspectorFooter } from "./InspectorFooter";
import { InspectorLayout } from "./InspectorLayout";
import { TriggerForm } from "./TriggerForm";

interface TriggerInspectorProps {
  trigger: Workflow.Trigger;
  onClose: () => void;
  onOpenRunPanel: (context: { jobId?: string; triggerId?: string }) => void;
}

/**
 * TriggerInspector - Composition layer for trigger configuration.
 * Currently just wraps form with layout (no actions yet).
 */
export function TriggerInspector({
  trigger,
  onClose,
  onOpenRunPanel,
}: TriggerInspectorProps) {
  const permissions = usePermissions();

  // Use centralized canRun hook for all run permission/state checks
  const { canRun, tooltipMessage: runTooltipMessage } = useCanRun();

  // Build footer with run button (only if user has permission)
  const footer = permissions?.can_edit_workflow ? (
    <InspectorFooter
      leftButtons={
        <Tooltip content={runTooltipMessage} side="top">
          <span className="inline-block">
            <Button
              variant="secondary"
              onClick={() => onOpenRunPanel({ triggerId: trigger.id })}
              disabled={!canRun}
            >
              Run
            </Button>
          </span>
        </Tooltip>
      }
    />
  ) : undefined;

  return (
    <InspectorLayout
      title="Inspector"
      nodeType="trigger"
      onClose={onClose}
      footer={footer}
    >
      <TriggerForm trigger={trigger} />
    </InspectorLayout>
  );
}
