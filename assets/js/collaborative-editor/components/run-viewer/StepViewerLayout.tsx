import type { ReactNode } from 'react';
import { Panel, PanelGroup, PanelResizeHandle } from 'react-resizable-panels';

import { RunTabPanel } from './RunTabPanel';

interface StepViewerLayoutProps {
  children: ReactNode;
}

/**
 * Shared layout component for run viewer tabs that displays the full
 * RunTabPanel (run metadata + step list) at the top and content viewer below.
 *
 * Used by LogTabPanel, InputTabPanel, and OutputTabPanel to provide
 * consistent layout and behavior.
 */
export function StepViewerLayout({ children }: StepViewerLayoutProps) {
  return (
    <PanelGroup direction="vertical" className="h-full">
      {/* Run metadata + Step list for navigation */}
      <Panel defaultSize={40} minSize={10} maxSize={80}>
        <RunTabPanel />
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
