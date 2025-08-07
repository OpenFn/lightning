/**
 * CollaborativeWorkflowDiagram - Wrapper for WorkflowDiagram using Yjs data
 * Phase 1: Basic rendering only - maps collaborative data to diagram format
 */

import React, { useState } from 'react';
import { useWorkflowStore } from '../../contexts/WorkflowStoreProvider';
import CollaborativeWorkflowDiagramImpl from './WorkflowDiagram';

interface CollaborativeWorkflowDiagramProps {
  className?: string;
}

export const CollaborativeWorkflowDiagram: React.FC<
  CollaborativeWorkflowDiagramProps
> = ({ className = 'h-full w-full' }) => {
  const { workflow } = useWorkflowStore();
  const [selection, setSelection] = useState<string | null>(null);

  const handleSelectionChange = (id: string | null) => {
    setSelection(id);
    // TODO: In Phase 2, sync this with collaborative selection
  };

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
      <CollaborativeWorkflowDiagramImpl
        selection={selection}
        onSelectionChange={handleSelectionChange}
        forceFit={true}
        showAiAssistant={false}
      />
    </div>
  );
};
