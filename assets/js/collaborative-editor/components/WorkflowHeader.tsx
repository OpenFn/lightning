/**
 * WorkflowHeader - Displays workflow id and name
 */

import type React from "react";

import { useWorkflowState } from "../hooks/Workflow";

export const WorkflowHeader: React.FC = () => {
  const workflow = useWorkflowState(state => state.workflow);

  if (!workflow) {
    return (
      <div className="mb-6">
        <div className="animate-pulse">
          <div className="h-8 bg-gray-200 rounded mb-2 w-3/4"></div>
          <div className="h-4 bg-gray-200 rounded w-1/2"></div>
        </div>
      </div>
    );
  }

  return (
    <div className="mb-6">
      <h2 className="text-2xl font-bold text-gray-900 mb-2">
        {workflow.name || "Untitled Workflow"}
      </h2>
      <p className="text-gray-600">
        Workflow ID: {workflow.id} • Real-time collaborative editing
      </p>
    </div>
  );
};
