import { cn } from '#/utils/cn';

import { Tooltip } from './Tooltip';

interface AIButtonProps {
  onClick?: () => void;
  disabled?: boolean;
  className?: string;
}

export function AIButton({
  onClick,
  disabled = true,
  className = '',
}: AIButtonProps) {
  return (
    <Tooltip
      content="AI chat is coming to the collaborative editor soon."
      side="bottom"
    >
      <button
        type="button"
        onClick={onClick}
        disabled={disabled}
        className={cn(
          'rounded-full bg-primary-600 p-2 text-white shadow-xs',
          'hover:bg-primary-500',
          'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600',
          'disabled:opacity-50 disabled:cursor-not-allowed',
          className
        )}
      >
        <span
          className="hero-chat-bubble-left-right size-5"
          aria-hidden="true"
        />
      </button>
    </Tooltip>
  );
}
