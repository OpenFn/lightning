import type { ReactNode } from 'react';

import { ErrorBoundary } from '../common/ErrorBoundary';

interface Props {
  children: ReactNode;
  onError?: (error: Error) => void;
}

export function RunViewerErrorBoundary({ children, onError }: Props) {
  return (
    <ErrorBoundary
      label="RunViewer"
      {...(onError ? { onError } : {})}
      fallback={(error, reset) => (
        <div className="flex items-center justify-center h-full">
          <div className="text-center">
            <p className="text-red-600 font-semibold">Something went wrong</p>
            <p className="text-sm text-gray-500 mt-1">{error.message}</p>
            <button
              onClick={reset}
              className="mt-4 px-4 py-2 bg-primary-100
                hover:bg-primary-200 rounded"
            >
              Try Again
            </button>
          </div>
        </div>
      )}
    >
      {children}
    </ErrorBoundary>
  );
}
