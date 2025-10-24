import { usePermissions } from "../../hooks/useSessionContext";
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

  // Permission checks for Run button
  // Note: can_run_workflow doesn't exist yet in permissions type
  // For Phase 2, we'll just use can_edit_workflow as a placeholder
  const canRun = permissions?.can_edit_workflow;

  // Build footer with run button (only if user has permission)
  const footer = permissions?.can_edit_workflow ? (
    <InspectorFooter
      leftButtons={
        <Tooltip
          content={
            !canRun
              ? "You do not have permission to run workflows"
              : "Run from this trigger"
          }
          side="top"
        >
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
