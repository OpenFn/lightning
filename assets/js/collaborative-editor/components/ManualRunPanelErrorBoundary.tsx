import { Component, type ReactNode } from 'react';

import { notifications } from '../lib/notifications';

interface Props {
  children: ReactNode;
  onError?: (error: Error) => void;
  onClose?: () => void;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

/**
 * Error boundary for ManualRunPanel
 *
 * Catches errors in the ManualRunPanel and its children, displaying a
 * user-friendly error message with options to retry or close the panel.
 *
 * Features:
 * - Displays error message from the caught error
 * - Provides "Try Again" button to reset error state
 * - Provides "Close Panel" button to exit the panel
 * - Logs errors to console for debugging
 * - Optionally calls onError callback for error reporting
 * - Shows toast notification when error occurs
 *
 * @example
 * ```tsx
 * <ManualRunPanelErrorBoundary onClose={handleClose}>
 *   <ManualRunPanel {...props} />
 * </ManualRunPanelErrorBoundary>
 * ```
 */
export class ManualRunPanelErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  override componentDidCatch(error: Error) {
    console.error('ManualRunPanel error:', error);

    // Show toast notification
    notifications.alert({
      title: 'Error loading run panel',
      description:
        error.message || 'An unexpected error occurred. Please try again.',
    });

    // Call optional error callback for error reporting
    this.props.onError?.(error);
  }

  handleReset = () => {
    this.setState({ hasError: false, error: null });
  };

  handleClose = () => {
    // Reset error state before closing
    this.setState({ hasError: false, error: null });
    this.props.onClose?.();
  };

  override render() {
    if (this.state.hasError) {
      return (
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
              {this.state.error?.message ||
                'An unexpected error occurred while loading the run panel.'}
            </p>

            <div className="flex gap-3 justify-center">
              <button
                onClick={this.handleReset}
                className="px-4 py-2 bg-primary-600 text-white rounded
                  hover:bg-primary-700 focus:outline-none focus:ring-2
                  focus:ring-primary-500 focus:ring-offset-2"
              >
                Try Again
              </button>

              {this.props.onClose && (
                <button
                  onClick={this.handleClose}
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
      );
    }

    return this.props.children;
  }
}
