import React, { Suspense } from 'react';

import { ErrorBoundary } from 'react-error-boundary';

import { Fallback } from './Fallback';

export type BoundaryProps = {
  children?: React.ReactNode;
};

/**
 * Some best practices:
 *
 * - Catch rendering errors and recover gracefully with an [error boundary](https://react.dev/reference/react/Component#catching-rendering-errors-with-an-error-boundary)
 *   TODO: Configure [`ErrorBoundary`](https://github.com/bvaughn/react-error-boundary#readme)
 * - Use a [suspense boundary](https://react.dev/reference/react/Suspense) to allow suspense features (such as `React.lazy`) to work.
 *   TODO: show a loading ("fallback") UI?
 */
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
// ESBuild renames the inner component to `Boundary2`
Boundary.displayName = 'Boundary';
