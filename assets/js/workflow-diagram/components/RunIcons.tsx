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
  failed: 'bg-red-200 text-red-500',
  crashed: 'bg-orange-200 text-orange-500 p-px',
};

export const renderIcon = (
  type?: string,
  options: Partial<{ tooltip: string; size: number }> = {}
) => {
  const { tooltip, size = 8 } = options;
  // switch (type) {
  //   case 'success':
  //     return Icon(type, { tooltip, size });
  // }
  if (!(type in STATE_COLORS)) {
    console.error('ERROR: Unknown run state:', type);
    // what do we do here?
    type = 'success';
  }
  return Icon(type!, { tooltip, size });
};

const Icon = (type: string, { tooltip, size }: any) => (
  <div
    className={`flex justify-center items-center  w-${size} h-${size} rounded-full ${STATE_COLORS[type]}`}
  >
    <span
      data-tooltip={tooltip}
      data-tooltip-placement="top"
      className={`${STATE_ICONS[type]} w-full h-full`}
    ></span>
  </div>
);
