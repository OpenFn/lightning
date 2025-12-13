import { Panel, PanelGroup, PanelResizeHandle } from 'react-resizable-panels';

import { cn } from '#/utils/cn';

import {
  useActiveRun,
  useActiveRunError,
  useActiveRunLoading,
  useHistoryCommands,
  useJobMatchesRun,
} from '../../hooks/useHistory';
import { useCurrentJob } from '../../hooks/useWorkflow';
import { isFinalState } from '../../types/history';

import { InputTabPanel } from './InputTabPanel';
import { LogTabPanel } from './LogTabPanel';
import { OutputTabPanel } from './OutputTabPanel';
import { RunSkeleton } from './RunSkeleton';
import { RunTabPanel } from './RunTabPanel';

type TabValue = 'log' | 'input' | 'output';

interface RunViewerPanelProps {
  followRunId: string | null;
  onClearFollowRun?: () => void;
  activeTab: TabValue;
  onTabChange: (tab: TabValue) => void;
}

export function RunViewerPanel({
  followRunId,
  activeTab,
  onTabChange: _onTabChange,
}: RunViewerPanelProps) {
  const run = useActiveRun();
  const isLoading = useActiveRunLoading();
  const error = useActiveRunError();
  const { clearActiveRunError } = useHistoryCommands();
  const { job: currentJob } = useCurrentJob();
  const jobMatchesRun = useJobMatchesRun(currentJob?.id || null);
  const shouldShowMismatch = !jobMatchesRun && run && isFinalState(run.state);

  // Note: Connection to run channel is managed by parent component (FullScreenIDE)
  // This component only reads the current run state from HistoryStore
  // Version mismatch banner is also handled by FullScreenIDE (above the tabs)

  // Empty state - no run to display
  if (!followRunId) {
    return (
      <div className="w-1/2 h-16 text-center m-auto p-4">
        <div className="text-gray-500 pb-2">
          After you click run, the logs and output will be visible here.
        </div>
      </div>
    );
  }

  // Loading state
  if (isLoading && !run) {
    return <RunSkeleton />;
  }

  // Error state
  if (error) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="text-center text-red-600">
          <p className="font-semibold">Error loading run</p>
          <p className="text-sm mt-1">{error}</p>
          <button
            onClick={clearActiveRunError}
            className="mt-4 px-4 py-2 bg-red-100
              hover:bg-red-200 rounded text-sm"
          >
            Dismiss
          </button>
        </div>
      </div>
    );
  }

  // No run data yet
  if (!run) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="text-gray-500">No run data available</div>
      </div>
    );
  }

  // Render with shared RunTabPanel at top and tab content below
  return (
    <PanelGroup
      direction="vertical"
      className={cn('h-full', shouldShowMismatch && 'opacity-50')}
      autoSaveId="lightning.run-viewer-layout"
    >
      {/* Shared Run metadata + Steps panel */}
      <Panel defaultSize={20} minSize={10} maxSize={40}>
        <RunTabPanel />
      </Panel>

      {/* Resize handle */}
      <PanelResizeHandle className="h-1 bg-gray-200 hover:bg-blue-400 transition-colors cursor-row-resize" />

      {/* Tab content (logs, input, or output) */}
      <Panel minSize={30}>
        <div className="h-full">
          {activeTab === 'log' && <LogTabPanel />}
          {activeTab === 'input' && <InputTabPanel />}
          {activeTab === 'output' && <OutputTabPanel />}
        </div>
      </Panel>
    </PanelGroup>
  );
}
