import { Tooltip } from '../../collaborative-editor/components/Tooltip';
import { cn } from '../../utils/cn';

const STATE_ICONS = {
  pending: 'hero-ellipsis-horizontal-circle-solid',
  success: 'hero-check-circle-solid',
  fail: 'hero-x-circle-solid',
  crash: 'hero-x-circle-solid',
  cancel: 'hero-no-symbol-solid',
  shield: 'hero-shield-exclamation-solid',
  clock: 'hero-clock-solid',
  circle_ex: 'hero-exclamation-circle-solid',
  triangle_ex: 'hero-exclamation-triangle-solid',
};

const STATE_COLORS = {
  pending: 'text-gray-400',
  success: 'text-green-500',
  fail: 'text-red-500',
  crash: 'text-orange-800',
  cancel: 'text-grey-600',
  shield: 'text-yellow-800',
  clock: 'text-yellow-800',
  circle_ex: 'text-yellow-800',
  triangle_ex: 'text-black-800',
};

export const renderIcon = (
  type: keyof typeof STATE_COLORS,
  options: Partial<{ tooltip: string }> = {}
) => {
  const { tooltip } = options;
  if (!(type in STATE_COLORS)) {
    console.error('ERROR: Unknown run state:', type);
    // Fallback to warning icon for unexpected states instead of success
    type = 'circle_ex';
  }

  const iconElement = (
    <div className="relative w-8 h-8 pointer-events-auto">
      {/* Draw a solid background behind the icon with a white fill */}
      <div className="absolute inset-0 w-6 h-6 ml-1 mt-1 bg-white rounded-full pointer-events-none" />
      {/* Render the icon itself */}
      <div
        className={cn(
          'relative flex justify-center items-center w-8 h-8 rounded-full pointer-events-none',
          STATE_COLORS[type]
        )}
      >
        <span
          className={cn(STATE_ICONS[type], 'w-full h-full pointer-events-none')}
        />
      </div>
    </div>
  );

  // If no tooltip provided, return icon without tooltip wrapper
  if (!tooltip) {
    return iconElement;
  }

  return (
    <Tooltip content={tooltip} side="top">
      {iconElement}
    </Tooltip>
  );
};
