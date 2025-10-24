import type { Workflow } from "../../types/workflow";

import { InspectorLayout } from "./InspectorLayout";
import { TriggerForm } from "./TriggerForm";

interface TriggerInspectorProps {
  trigger: Workflow.Trigger;
  onClose: () => void;
}

/**
 * TriggerInspector - Composition layer for trigger configuration.
 * Currently just wraps form with layout (no actions yet).
 */
export function TriggerInspector({ trigger, onClose }: TriggerInspectorProps) {
  return (
    <InspectorLayout title="Inspector" nodeType="trigger" onClose={onClose}>
      <TriggerForm trigger={trigger} />
    </InspectorLayout>
  );
}
