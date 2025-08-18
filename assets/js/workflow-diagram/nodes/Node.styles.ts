interface StatusDetails {
  icon: string;
  color: string;
  border: string;
  text: string;
}

type RunStatus =
  | 'success'
  | 'fail'
  | 'crash'
  | 'cancel'
  | 'kill'
  | 'exception'
  | 'lost';

export const RUN_DATA_ICON: Record<RunStatus, StatusDetails> = {
  success: {
    icon: 'hero-check-circle',
    color: 'bg-green-100',
    border: 'border-green-600',
    text: 'text-green-600',
  },
  fail: {
    icon: 'hero-x-circle',
    color: 'bg-red-100',
    border: 'border-red-600',
    text: 'text-red-600',
  },
  crash: {
    icon: 'hero-exclamation-triangle',
    color: 'bg-orange-100',
    border: 'border-orange-600',
    text: 'text-orange-600',
  },
  cancel: {
    icon: 'hero-no-symbo',
    color: 'bg-gray-100',
    border: 'border-gray-600',
    text: 'text-gray-600',
  },
  kill: {
    icon: 'hero-shield-exclamation',
    color: 'bg-purple-100',
    border: 'border-purple-600',
    text: 'text-purple-600',
  },
  exception: {
    icon: 'hero-exclamation-circle',
    color: 'bg-yellow-100',
    border: 'border-yellow-600',
    text: 'text-yellow-600',
  },
  lost: {
    icon: 'hero-question-mark-circle',
    color: 'bg-blue-100',
    border: 'border-blue-600',
    text: 'text-blue-600',
  },
};
