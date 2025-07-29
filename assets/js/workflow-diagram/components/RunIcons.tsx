// TODO: to be put somewhere else
const STATE_ICONS = {
  rejected: 'hero-x-circle',
  pending: 'hero-clock',
  running: 'hero-play-circle',
  available: 'hero-clock',
  claimed: 'hero-arrow-right-circle',
  started: 'hero-play-circle',
  success: 'hero-check-circle',
  failed: 'hero-x-circle',
  crashed: 'hero-exclamation-triangle',
  cancelled: 'hero-no-symbol',
  killed: 'hero-shield-exclamation',
  exception: 'hero-exclamation-circle',
  lost: 'hero-question-mark-circle',
};

const STATE_COLORS = {
  success: 'bg-green-200 text-green-500',
};

export const icon = (type: string, tooltip?: string) => {
  switch (type) {
    case 'success':
      return SuccessIcon({ tooltip });
  }
  return SuccessIcon({ tooltip });
};

// absolute -left-2 -top-2
export const SuccessIcon = ({ tooltip }: any) => (
  <div
    className={`flex justify-center items-center  w-8 h-8 rounded-full ${STATE_COLORS.success}`}
  >
    <span
      data-tooltip={tooltip}
      data-tooltip-placement="top"
      className={`${STATE_ICONS.success} w-full h-full`}
    ></span>
  </div>
);
