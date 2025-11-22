interface RightPanelEmptyStateProps {
  onBrowseHistory: () => void;
  onCreateRun: () => void;
}

export function RightPanelEmptyState({
  onBrowseHistory,
  onCreateRun,
}: RightPanelEmptyStateProps) {
  return (
    <div
      className="flex flex-col items-center justify-center
        h-full gap-4 p-8"
    >
      <button
        type="button"
        onClick={onBrowseHistory}
        className="flex flex-col items-center justify-center w-full
          max-w-sm aspect-square p-8 text-lg font-medium text-gray-700
          bg-white border-2 border-gray-300 rounded-lg
          hover:border-blue-500 hover:bg-blue-50 transition-colors
          focus:outline-none focus:ring-2 focus:ring-blue-500
          focus:ring-offset-2"
      >
        <span className="hero-clock h-8 w-8 mb-2" />
        <span>Browse History</span>
        <span className="text-sm text-gray-500 mt-1 font-normal">
          Pick a run to inspect
        </span>
      </button>

      <button
        type="button"
        onClick={onCreateRun}
        className="flex flex-col items-center justify-center w-full
          max-w-sm aspect-square p-8 text-lg font-medium text-gray-700
          bg-white border-2 border-gray-300 rounded-lg
          hover:border-green-500 hover:bg-green-50 transition-colors
          focus:outline-none focus:ring-2 focus:ring-green-500
          focus:ring-offset-2"
      >
        <span className="hero-play h-8 w-8 mb-2" />
        <span>Create New Run</span>
        <span className="text-sm text-gray-500 mt-1 font-normal">
          Select input and execute
        </span>
      </button>
    </div>
  );
}
