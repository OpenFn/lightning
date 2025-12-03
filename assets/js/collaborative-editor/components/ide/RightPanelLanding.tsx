import { ClockIcon, PlayIcon } from '@heroicons/react/24/outline';

import { Button } from '../Button';

interface RightPanelLandingProps {
  onSelectHistory: () => void;
  onCreateRun: () => void;
}

export function RightPanelLanding({
  onSelectHistory,
  onCreateRun,
}: RightPanelLandingProps) {
  return (
    <div className="flex flex-col items-center justify-center h-full p-8">
      <div className="flex flex-col gap-4 w-full max-w-48">
        <Button
          variant="secondary"
          onClick={onSelectHistory}
          className="flex flex-col items-center justify-center gap-2 py-6 aspect-square"
        >
          <ClockIcon className="h-8 w-8" />
          <span>View History</span>
        </Button>
        <Button
          variant="secondary"
          onClick={onCreateRun}
          className="flex flex-col items-center justify-center gap-2 py-6 aspect-square"
        >
          <PlayIcon className="h-8 w-8" />
          <span>Create Run</span>
        </Button>
      </div>
    </div>
  );
}
