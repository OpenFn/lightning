import type { ReactNode } from 'react';
import { Panel, PanelGroup, PanelResizeHandle } from 'react-resizable-panels';

import { useActiveRun, useHistoryCommands } from '../../hooks/useHistory';

import { StepList } from './StepList';

interface StepViewerLayoutProps {
  children: ReactNode;
  selectedStepId: string | null;
}

/**
 * Shared layout component for run viewer tabs that displays a resizable
 * step list at the top and content viewer below.
 *
 * Used by LogTabPanel, InputTabPanel, and OutputTabPanel to provide
 * consistent layout and behavior.
 */
export function StepViewerLayout({
  children,
  selectedStepId,
}: StepViewerLayoutProps) {
  const run = useActiveRun();
  const { selectStep } = useHistoryCommands();

  if (!run) {
    return <div className="p-4 text-gray-500">No run selected</div>;
  }

  return (
    <PanelGroup direction="vertical" className="h-full">
      {/* Step list for navigation */}
      <Panel defaultSize={20} minSize={10} maxSize={40}>
        <div className="h-full overflow-auto border-b p-4">
          <StepList
            steps={run.steps}
            selectedStepId={selectedStepId}
            onSelectStep={selectStep}
          />
        </div>
      </Panel>

      {/* Resize handle */}
      <PanelResizeHandle className="h-1 bg-gray-200 hover:bg-blue-400 transition-colors cursor-row-resize" />

      {/* Content viewer (logs, input, or output) */}
      <Panel minSize={30}>
        <div className="h-full">{children}</div>
      </Panel>
    </PanelGroup>
  );
}
