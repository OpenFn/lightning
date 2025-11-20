import type { RunDetail } from '../../types/history';

interface StatePillProps {
  state: RunDetail['state'];
}

// Ported from lib/lightning_web/live/run_live/components.ex:94-125
export function StatePill({ state }: StatePillProps) {
  const chipStyles: Record<RunDetail['state'], string> = {
    // work order states
    available: 'bg-gray-200 text-gray-800',
    claimed: 'bg-blue-200 text-blue-800',
    started: 'bg-blue-200 text-blue-800',
    // final states
    success: 'bg-green-200 text-green-800',
    failed: 'bg-red-200 text-red-800',
    crashed: 'bg-orange-200 text-orange-800',
    cancelled: 'bg-gray-500 text-gray-800',
    killed: 'bg-yellow-200 text-yellow-800',
    exception: 'bg-gray-800 text-white',
    lost: 'bg-gray-800 text-white',
  };

  const displayText = (state: RunDetail['state']): string => {
    switch (state) {
      case 'available':
        return 'Enqueued';
      case 'claimed':
        return 'Starting';
      case 'started':
        return 'Running';
      default:
        return state.charAt(0).toUpperCase() + state.slice(1);
    }
  };

  const classes = chipStyles[state] || 'bg-gray-200 text-gray-800';
  const text = displayText(state);

  return (
    <span
      className={`
        my-auto whitespace-nowrap rounded-full
        py-2 px-4 text-center align-baseline
        text-xs font-medium leading-none
        ${classes}
      `}
    >
      {text}
    </span>
  );
}
