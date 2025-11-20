import { useEffect } from 'react';

import { cn } from '#/utils/cn';

interface AIAssistantPanelProps {
  isOpen: boolean;
  onClose: () => void;
  children?: React.ReactNode;
  /**
   * Whether this panel is inside a resizable Panel component (IDE mode)
   * or standalone with fixed width (Canvas mode)
   */
  isResizable?: boolean;
}

/**
 * AI Assistant Panel Component
 *
 * Full-height right-side panel similar to Google Cloud Assistant.
 * Pushes content to the left when open (not an overlay).
 *
 * Design Specifications:
 * - Positioned on the right side, pushes content left when open
 * - Full viewport height
 * - Resizable in IDE mode, fixed 400px width in Canvas mode
 * - Smooth slide-in/out transitions
 * - No backdrop overlay (content pushes instead of overlaying)
 * - Escape key to close
 */
export function AIAssistantPanel({
  isOpen,
  onClose,
  children,
  isResizable = false,
}: AIAssistantPanelProps) {
  // Handle escape key to close panel
  useEffect(() => {
    const handleEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && isOpen) {
        onClose();
      }
    };

    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [isOpen, onClose]);

  return (
    <div
      className={cn(
        'h-full flex flex-col overflow-hidden bg-slate-100',
        !isResizable && [
          'flex-none border-l border-gray-200',
          'transition-all duration-300 ease-in-out',
          isOpen ? 'w-[400px]' : 'w-0 border-l-0',
        ]
      )}
      role="dialog"
      aria-modal="false"
      aria-label="AI Assistant"
    >
      {/* Panel Header */}
      <div className="flex-none bg-white shadow-xs border-b border-gray-200">
        <div className="mx-auto sm:px-6 lg:px-8 py-6 flex items-center justify-between h-20 text-sm">
          <div className="flex items-center gap-3">
            <img src="/images/logo.svg" alt="OpenFn" className="size-5" />
            <h2 className="text-base font-semibold text-gray-900">Assistant</h2>
          </div>
          <button
            type="button"
            onClick={onClose}
            className={cn(
              'rounded-md text-gray-400 hover:text-gray-600',
              'hover:bg-gray-100 transition-colors',
              'focus:outline-none focus:ring-2 focus:ring-primary-500',
              'flex-shrink-0 p-1.5'
            )}
            aria-label="Close AI Assistant"
          >
            <span className="hero-x-mark h-5 w-5" />
          </button>
        </div>
      </div>

      {/* Panel Content */}
      <div className="flex-1 overflow-y-auto bg-white">{children}</div>
    </div>
  );
}
