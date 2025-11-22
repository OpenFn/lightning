import {
  useHistory,
  useHistoryLoading,
  useHistoryError,
  useHistoryCommands,
} from '../../hooks/useHistory';
import type { RunSummary } from '../../types/history';
import { HistoryList } from '../diagram/HistoryList';

interface HistoryBrowserPanelProps {
  onSelectRun: (runId: string) => void;
  onClose: () => void;
  projectId: string;
  workflowId: string;
}

export function HistoryBrowserPanel({
  onSelectRun,
  onClose,
}: HistoryBrowserPanelProps) {
  const workOrders = useHistory();
  const isLoading = useHistoryLoading();
  const error = useHistoryError();
  const { requestHistory } = useHistoryCommands();

  const handleSelectRun = (run: RunSummary) => {
    onSelectRun(run.id);
  };

  const handleRetry = () => {
    void requestHistory();
  };

  return (
    <div className="flex flex-col h-full bg-white">
      {/* Header */}
      <div
        className="flex items-center gap-2 px-4 py-3 border-b
          border-gray-200 shrink-0"
      >
        <button
          type="button"
          onClick={onClose}
          className="text-gray-400 hover:text-gray-600 transition-colors"
          aria-label="Close history browser"
        >
          <span className="hero-arrow-left h-4 w-4" />
        </button>
        <h2 className="text-sm font-medium text-gray-700">Browse History</h2>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        {workOrders.length === 0 && !isLoading && !error ? (
          // Empty history state
          <div
            className="flex flex-col items-center justify-center
              h-full p-8 text-center"
          >
            <span className="hero-clock h-12 w-12 text-gray-300 mb-4" />
            <h3 className="text-lg font-medium text-gray-700 mb-2">
              No Runs Yet
            </h3>
            <p className="text-sm text-gray-500 mb-6">
              This workflow hasn't been executed yet. Create your first run to
              see it here.
            </p>
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-sm font-medium text-white bg-blue-600
                rounded hover:bg-blue-700 transition-colors"
            >
              Create First Run
            </button>
          </div>
        ) : (
          <HistoryList
            history={workOrders}
            selectRunHandler={handleSelectRun}
            loading={isLoading}
            error={error}
            onRetry={handleRetry}
          />
        )}
      </div>
    </div>
  );
}
