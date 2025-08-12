import type React from "react";
import type { Workflow } from "../types";

interface TriggerInspectorProps {
  trigger: Workflow.Trigger;
}

export const TriggerInspector: React.FC<TriggerInspectorProps> = ({
  trigger,
}) => {
  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-2">
          Trigger Details
        </h3>
        <div className="space-y-2">
          <div>
            <label className="text-xs text-gray-500">Name</label>
            <p className="text-sm text-gray-900">{trigger.name}</p>
          </div>
          <div>
            <label className="text-xs text-gray-500">Type</label>
            <p className="text-sm text-gray-900">{trigger.type}</p>
          </div>
          <div>
            <label className="text-xs text-gray-500">Enabled</label>
            <p className="text-sm text-gray-900">
              {trigger.enabled ? "Yes" : "No"}
            </p>
          </div>
          <div>
            <label className="text-xs text-gray-500">ID</label>
            <p className="text-xs text-gray-500 font-mono">{trigger.id}</p>
          </div>
        </div>
      </div>
    </div>
  );
};
