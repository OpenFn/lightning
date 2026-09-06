import { type ReactNode, useCallback } from 'react';

import { notifications } from '../lib/notifications';

import { ErrorBoundary } from './common/ErrorBoundary';

interface Props {
  children: ReactNode;
  onError?: (error: Error) => void;
  onClose?: () => void;
}

/**
 * Error boundary for ManualRunPanel
 *
 * Catches errors in the ManualRunPanel and its children, displaying a
 * user-friendly error message with options to retry or close the panel. Also
 * raises a toast, since the panel can be off-screen when it fails.
 *
 * @example
 * ```tsx
 * <ManualRunPanelErrorBoundary onClose={handleClose}>
 *   <ManualRunPanel {...props} />
 * </ManualRunPanelErrorBoundary>
 * ```
 */
export function ManualRunPanelErrorBoundary({
  children,
  onError,
  onClose,
}: Props) {
  const handleError = useCallback(
    (error: Error) => {
      notifications.alert({
        title: 'Error loading run panel',
        description:
          error.message || 'An unexpected error occurred. Please try again.',
      });
      onError?.(error);
    },
    [onError]
  );

  return (
    <ErrorBoundary
      label="ManualRunPanel"
      onError={handleError}
      fallback={(error, reset) => (
        <div className="flex items-center justify-center h-full p-8">
          <div className="text-center max-w-md">
            <div className="mb-4">
              <svg
                className="mx-auto h-12 w-12 text-red-600"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                />
              </svg>
            </div>

            <h3 className="text-lg font-semibold text-gray-900 mb-2">
              Something went wrong
            </h3>

            <p className="text-sm text-gray-600 mb-6">
              {error.message ||
                'An unexpected error occurred while loading the run panel.'}
            </p>

            <div className="flex gap-3 justify-center">
              <button
                onClick={reset}
                className="px-4 py-2 bg-primary-600 text-white rounded
                  hover:bg-primary-700 focus:outline-none focus:ring-2
                  focus:ring-primary-500 focus:ring-offset-2"
              >
                Try Again
              </button>

              {onClose && (
                <button
                  onClick={() => {
                    // Reset before closing so reopening the panel isn't stuck
                    // on the error state.
                    reset();
                    onClose();
                  }}
                  className="px-4 py-2 bg-gray-200 text-gray-900 rounded
                    hover:bg-gray-300 focus:outline-none focus:ring-2
                    focus:ring-gray-500 focus:ring-offset-2"
                >
                  Close Panel
                </button>
              )}
            </div>
          </div>
        </div>
      )}
    >
      {children}
    </ErrorBoundary>
  );
}
