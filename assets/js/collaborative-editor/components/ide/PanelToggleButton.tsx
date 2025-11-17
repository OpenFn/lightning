import { cn } from '#/utils/cn';

interface PanelToggleButtonProps {
  isCollapsed: boolean;
  onClick: () => void;
  disabled?: boolean;
  ariaLabel: string;
  className?: string;
}

/**
 * Circular toggle button for collapsing/expanding IDE panels
 * Shows minus icon when expanded, plus icon when collapsed
 */
export function PanelToggleButton({
  isCollapsed,
  onClick,
  disabled = false,
  ariaLabel,
  className,
}: PanelToggleButtonProps) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={cn(
        'disabled:opacity-30 disabled:cursor-not-allowed',
        className
      )}
      aria-label={ariaLabel}
    >
      <span
        className={cn(
          'w-5 h-5 hover:bg-slate-400 text-slate-500',
          isCollapsed ? 'hero-plus-circle' : 'hero-minus-circle'
        )}
        aria-hidden="true"
      />
    </button>
  );
}
