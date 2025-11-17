import {
  useCurrentRun,
  useRunActions,
  useRunError,
  useRunLoading,
} from '../../hooks/useRun';

import { InputTabPanel } from './InputTabPanel';
import { LogTabPanel } from './LogTabPanel';
import { OutputTabPanel } from './OutputTabPanel';
import { RunSkeleton } from './RunSkeleton';
import { RunTabPanel } from './RunTabPanel';

type TabValue = 'run' | 'log' | 'input' | 'output';

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
  const run = useCurrentRun();
  const isLoading = useRunLoading();
  const error = useRunError();
  const { clearError } = useRunActions();

  // Note: Connection to run channel is managed by parent component (FullScreenIDE)
  // This component only reads the current run state from RunStore

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
            onClick={clearError}
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

  // Render tab content based on activeTab prop
  return (
    <div
      className="h-full flex flex-col"
      role="region"
      aria-label="Run output viewer"
    >
      <div className="flex-1 overflow-hidden">
        {activeTab === 'run' && <RunTabPanel />}
        {activeTab === 'log' && <LogTabPanel />}
        {activeTab === 'input' && <InputTabPanel />}
        {activeTab === 'output' && <OutputTabPanel />}
      </div>
    </div>
  );
}
