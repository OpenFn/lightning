import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

interface ActionButtonProps {
  children: ReactNode;
  onClick?: () => void;
  disabled?: boolean;
  /** Renders a spinner and disables the button. */
  loading?: boolean;
  type?: 'button' | 'submit';
  className?: string;
}

/**
 * Primary action button for the new design system: the gray-900 pill used by
 * the landing screen's modals. Distinct from `Button.tsx`, which is the older
 * `primary-600` / `rounded-md` system still used across the inspector and
 * header. The two coexist until the design system transition completes.
 */
export function ActionButton({
  children,
  onClick,
  disabled = false,
  loading = false,
  type = 'button',
  className,
}: ActionButtonProps) {
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled || loading}
      className={cn(
        'inline-flex items-center gap-2 rounded-full bg-gray-900 px-5 py-2',
        'text-sm font-semibold text-white transition-colors',
        'hover:bg-gray-700',
        'focus:outline-none focus-visible:ring focus-visible:ring-gray-300',
        'disabled:opacity-40 disabled:hover:bg-gray-900 disabled:cursor-not-allowed',
        className
      )}
    >
      {loading && (
        <svg
          aria-hidden="true"
          className="animate-spin h-4 w-4"
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
        >
          <circle
            className="opacity-25"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            strokeWidth="4"
          />
          <path
            className="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
          />
        </svg>
      )}
      {children}
    </button>
  );
}
