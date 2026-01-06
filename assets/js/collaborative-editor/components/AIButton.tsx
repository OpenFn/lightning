import { cn } from '#/utils/cn';

import { useIsAIAssistantPanelOpen, useUICommands } from '../hooks/useUI';

import { ShortcutKeys } from './ShortcutKeys';
import { Tooltip } from './Tooltip';

interface AIButtonProps {
  onClick?: () => void;
  disabled?: boolean;
  disabledMessage?: string;
  className?: string;
}

export function AIButton({
  onClick,
  disabled = false,
  disabledMessage,
  className = '',
}: AIButtonProps) {
  const { toggleAIAssistantPanel, collapseCreateWorkflowPanel } =
    useUICommands();
  const isOpen = useIsAIAssistantPanelOpen();

  const handleClick = () => {
    if (onClick) {
      onClick();
    } else {
      // Close create workflow panel when opening AI Assistant
      if (!isOpen) {
        collapseCreateWorkflowPanel();
      }
      toggleAIAssistantPanel();
    }
  };

  return (
    <Tooltip
      content={
        disabled && disabledMessage ? (
          disabledMessage
        ) : (
          <>
            {isOpen ? 'Close AI Assistant' : 'Open AI Assistant'} (
            <ShortcutKeys keys={['mod', 'k']} />)
          </>
        )
      }
      side="bottom"
    >
      <button
        type="button"
        onClick={handleClick}
        disabled={disabled}
        className={cn(
          'rounded-full p-2',
          'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600',
          'disabled:opacity-50 disabled:cursor-not-allowed',
          isOpen
            ? 'bg-primary-600 text-white hover:enabled:bg-primary-500'
            : 'bg-primary-100 text-primary-600 hover:enabled:bg-primary-200',
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
