import React, { useEffect, useRef } from 'react';
import tippy, { type Instance as TippyInstance } from 'tippy.js';

interface AiAssistantToggleProps {
  showAiAssistant?: boolean | undefined;
  canEditWorkflow?: boolean | undefined;
  snapshotVersionTag?: string | undefined;
  aiAssistantEnabled?: boolean | undefined;
  liveAction?: string | undefined;
  drawerWidth: number;
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
  const containerRef = useRef<HTMLDivElement>(null);
  const tippyInstanceRef = useRef<TippyInstance | null>(null);

  const isDisabled = snapshotVersionTag !== 'latest';

  const tooltipText = isDisabled
    ? 'Switch to the latest version of this workflow to use the AI Assistant.'
    : showAiAssistant === true
      ? 'Click to close the AI Assistant'
      : 'Click to open the AI Assistant';

  useEffect(() => {
    if (!containerRef.current) return;

    tippyInstanceRef.current = tippy(containerRef.current, {
      placement: 'right',
      content: tooltipText,
    });

    return () => {
      if (tippyInstanceRef.current) {
        tippyInstanceRef.current.destroy();
        tippyInstanceRef.current = null;
      }
    };
  }, []);

  useEffect(() => {
    if (tippyInstanceRef.current) {
      tippyInstanceRef.current.setContent(tooltipText);
    }
  }, [tooltipText]);

  const shouldShow =
    canEditWorkflow && aiAssistantEnabled && liveAction === 'edit';

  if (!shouldShow) return null;

  const buttonClasses = [
    'flex items-center justify-between pl-3 pr-3 py-2 transition-all duration-200 w-full text-left',
    isDisabled
      ? 'bg-gray-200 text-gray-500 cursor-not-allowed opacity-60'
      : 'bg-gray-50 hover:bg-gray-100 text-gray-700 hover:shadow-sm',
  ].join(' ');

  const containerClasses = [
    'absolute left-4 top-4 z-30 bg-white rounded-lg shadow-sm overflow-hidden transition-all duration-300 ease-in-out',
    isDisabled ? 'border border-gray-300 opacity-75' : 'border border-gray-200',
  ].join(' ');

  const iconClasses = [
    'w-4 h-4 mr-3 transition-colors duration-200',
    isDisabled ? 'text-gray-400' : 'text-gray-500',
  ].join(' ');

  const textClasses = [
    'text-sm font-medium transition-colors duration-200',
    isDisabled ? 'text-gray-500' : 'text-gray-700',
  ].join(' ');

  return (
    <div
      ref={containerRef}
      id="AiAssistantToggle"
      className={containerClasses}
      style={{
        transform: `translateX(${drawerWidth}px)`,
        transition: 'transform 300ms ease-in-out',
      }}
    >
      <button
        id="AiAssistantToggleBtn"
        type="button"
        disabled={isDisabled}
        className={buttonClasses}
        {...(!isDisabled && { 'phx-click': 'toggle-workflow-ai-chat' })}
      >
        <div className="flex items-center gap-2">
          <span className={textClasses}>AI Assistant</span>
        </div>
        <div className={iconClasses}>
          {showAiAssistant ? <ChevronLeftIcon /> : <ChevronRightIcon />}
        </div>
      </button>
    </div>
  );
};
