import { cn } from '#/utils/cn';

interface BadgeProps {
  onClose?: () => void;
  className?: string;
  variant?: 'default' | 'warning';
}

const Badge: React.FC<React.PropsWithChildren<BadgeProps>> = ({
  children,
  onClose,
  className,
  variant = 'default',
}) => {
  return (
    <div
      className={cn(
        'inline-flex items-center gap-x-1',
        'rounded-md px-2 py-1 text-xs font-medium',
        variant === 'default' && 'bg-blue-100 text-blue-700',
        variant === 'warning' && 'bg-yellow-100 text-yellow-800',
        className
      )}
    >
      <span className="flex items-center">{children}</span>
      {onClose && (
        <button
          onClick={onClose}
          className={cn(
            'group relative -mr-1 flex items-center justify-center h-3.5 w-3.5 rounded-sm',
            variant === 'default' && 'hover:bg-blue-600/20',
            variant === 'warning' && 'hover:bg-yellow-700/20'
          )}
          aria-label="Remove"
          title="Remove"
        >
          <span className="sr-only">Remove</span>
          <span className="hero-x-mark h-3.5 w-3.5" />
        </button>
      )}
    </div>
  );
};

export default Badge;
