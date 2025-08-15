import React, { useState, useEffect } from 'react';

interface AiAssistantToggleProps {
  showAiAssistant: boolean;
  canEditWorkflow: boolean;
  snapshotVersionTag: string;
  aiAssistantEnabled: boolean;
  liveAction: string;
  drawerWidth: number; // Add drawerWidth prop
}

const ChevronLeftIcon = () => (
  <svg
    className="w-4 h-4 ml-3"
    fill="none"
    stroke="currentColor"
    viewBox="0 0 24 24"
  >
    <path
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth={2}
      d="M15 19l-7-7 7-7"
    />
  </svg>
);

const ChevronRightIcon = () => (
  <svg
    className="w-4 h-4 ml-3"
    fill="none"
    stroke="currentColor"
    viewBox="0 0 24 24"
  >
    <path
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth={2}
      d="M9 5l7 7-7 7"
    />
  </svg>
);

export const AiAssistantToggle: React.FC<AiAssistantToggleProps> = ({
  showAiAssistant,
  canEditWorkflow,
  snapshotVersionTag,
  aiAssistantEnabled,
  liveAction,
  drawerWidth,
}) => {
  const [isVisible, setIsVisible] = useState(false);

  const shouldShow =
    snapshotVersionTag === 'latest' &&
    canEditWorkflow &&
    aiAssistantEnabled &&
    liveAction === 'edit';

  useEffect(() => {
    if (shouldShow) {
      const timer = setTimeout(() => setIsVisible(true), 500);
      return () => clearTimeout(timer);
    } else {
      setIsVisible(false);
    }
  }, [shouldShow]);

  if (!shouldShow) return null;

  const ariaLabel =
    snapshotVersionTag !== 'latest'
      ? 'Switch to the latest version of this workflow to use the AI Assistant.'
      : showAiAssistant
      ? 'Click to close the AI Assistant'
      : 'Click to open the AI Assistant';

  const buttonClasses = [
    'flex items-center justify-between pl-3 pr-3 py-2 transition-colors w-full text-left',
    snapshotVersionTag !== 'latest'
      ? 'bg-gray-100 text-gray-400 cursor-not-allowed'
      : 'bg-gray-50 hover:bg-gray-100 text-gray-700',
  ].join(' ');

  const iconClasses =
    snapshotVersionTag === 'latest'
      ? 'w-4 h-4 mr-3 text-gray-300'
      : 'w-4 h-4 text-gray-400';

  return (
    <div
        id="AiAssistantToggle"
      className={`absolute left-4 top-4 z-30 bg-white border border-gray-200 rounded-lg shadow-sm overflow-hidden transition-all duration-300 ease-in-out ${
        isVisible ? 'opacity-100' : 'opacity-0'
      }`}
      style={{
        transform: `translateX(${drawerWidth}px)`,
        transition: 'transform 300ms ease-in-out, opacity 500ms',
      }}
      data-phx-hook="Tooltip"
      aria-label={ariaLabel}
    >
      <button
        id="AiAssistantToggleButton"
        type="button"
        disabled={snapshotVersionTag !== 'latest'}
        className={buttonClasses}
        data-phx-hook="AiAssistantToggle"
      >
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium">AI Assistant</span>
        </div>
        <div className={iconClasses}>
          {showAiAssistant ? <ChevronLeftIcon /> : <ChevronRightIcon />}
        </div>
      </button>
    </div>
  );
};
