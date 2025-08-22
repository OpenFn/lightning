/**
 * CollaborativeWorkflowDiagram - Wrapper for WorkflowDiagram using Yjs data
 * Phase 1: Basic rendering only - maps collaborative data to diagram format
 */

import { ReactFlowProvider } from "@xyflow/react";
import type React from "react";

import { useNodeSelection, useWorkflowState } from "../../hooks/useWorkflow";

import CollaborativeWorkflowDiagramImpl from "./WorkflowDiagram";

interface CollaborativeWorkflowDiagramProps {
  className?: string;
  inspectorId?: string;
}

export const CollaborativeWorkflowDiagram: React.FC<
  CollaborativeWorkflowDiagramProps
> = ({ className = "h-full w-full", inspectorId }) => {
  const workflow = useWorkflowState(state => state.workflow);
  const { currentNode, selectNode } = useNodeSelection();

  // Don't render if no workflow data yet
  if (!workflow) {
    return (
      <div className={`flex items-center justify-center ${className}`}>
        <div className="text-center text-gray-500">
          <p>Loading workflow diagram...</p>
        </div>
      </div>
    );
  }

  return (
    <div className={className}>
      <ReactFlowProvider>
        <CollaborativeWorkflowDiagramImpl
          selection={currentNode.id}
          onSelectionChange={selectNode}
          forceFit={true}
          showAiAssistant={false}
          inspectorId={inspectorId}
        />
      </ReactFlowProvider>
    </div>
  );
};
