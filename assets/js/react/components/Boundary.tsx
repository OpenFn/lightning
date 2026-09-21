import * as Sentry from '@sentry/react';
import React, { Suspense } from 'react';
import { ErrorBoundary } from 'react-error-boundary';

import { Fallback } from './Fallback';

const reportError = (error: unknown, info: React.ErrorInfo) => {
  Sentry.captureReactException(error, info, {
    tags: { errorBoundary: 'Boundary' },
  });
};

export type BoundaryProps = {
  children?: React.ReactNode;
};

export const Boundary = React.forwardRef<HTMLDivElement, BoundaryProps>(
  function Boundary({ children }, ref) {
    return (
      <ErrorBoundary FallbackComponent={Fallback} onError={reportError}>
        <Suspense>
          <div ref={ref} style={{ display: 'contents' }}>
            {children}
          </div>
        </Suspense>
      </ErrorBoundary>
    );
  }
);

Boundary.displayName = 'Boundary';
