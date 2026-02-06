import { cn } from '#/utils/cn';

interface SpinnerProps {
  size?: 'sm' | 'md' | 'lg';
  className?: string;
}

/**
 * Spinner - Reusable loading spinner using heroicons
 *
 * Uses the `hero-arrow-path` icon with Tailwind's `animate-spin` class,
 * following the established pattern across the collaborative-editor.
 *
 * @example
 * <Spinner size="md" />
 * <Spinner size="sm" className="text-primary-500" />
 */
export function Spinner({ size = 'md', className }: SpinnerProps) {
  const sizeClasses = {
    sm: 'h-3.5 w-3.5',
    md: 'h-4 w-4',
    lg: 'h-5 w-5',
  };

  return (
    <span
      className={cn(
        'hero-arrow-path animate-spin',
        sizeClasses[size],
        className
      )}
      aria-label="Loading"
    />
  );
}
