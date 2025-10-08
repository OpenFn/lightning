/**
 * SuccessNotification - Success banner for workflow import
 *
 * Displays a temporary success message with auto-dismiss
 */

import { useEffect } from 'react';

interface SuccessNotificationProps {
  message: string;
  onDismiss: () => void;
  autoDismissMs?: number;
}

export function SuccessNotification({
  message,
  onDismiss,
  autoDismissMs = 3000,
}: SuccessNotificationProps) {
  useEffect(() => {
    const timer = setTimeout(onDismiss, autoDismissMs);
    return () => clearTimeout(timer);
  }, [onDismiss, autoDismissMs]);

  return (
    <div
      className="absolute top-4 left-1/2 -translate-x-1/2 z-50 bg-green-100 border border-green-200 text-green-800 px-4 py-3 rounded-lg shadow-lg flex items-center gap-3 min-w-80 animate-in fade-in slide-in-from-top-2 duration-300"
      role="alert"
    >
      <svg
        className="w-5 h-5 text-green-600 shrink-0"
        fill="currentColor"
        viewBox="0 0 20 20"
      >
        <path
          fillRule="evenodd"
          d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
          clipRule="evenodd"
        />
      </svg>
      <p className="text-sm font-medium flex-grow">{message}</p>
      <button
        onClick={onDismiss}
        className="shrink-0 text-green-600 hover:text-green-800"
        aria-label="Dismiss"
      >
        <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
          <path
            fillRule="evenodd"
            d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
            clipRule="evenodd"
          />
        </svg>
      </button>
    </div>
  );
}
