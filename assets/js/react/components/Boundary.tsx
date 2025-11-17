import React, { Suspense } from 'react';
import { ErrorBoundary } from 'react-error-boundary';

import { Fallback } from './Fallback';

export type BoundaryProps = {
  children?: React.ReactNode;
};

export const Boundary = React.forwardRef<HTMLDivElement, BoundaryProps>(
  function Boundary({ children }, ref) {
    return (
      <ErrorBoundary FallbackComponent={Fallback}>
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
