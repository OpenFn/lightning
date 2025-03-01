import { StrictMode, Suspense } from 'react';

import { ErrorBoundary } from 'react-error-boundary';

import { Fallback } from './Fallback';

export type BoundaryProps = {
  children?: React.ReactNode;
};

/**
 * Some best practices:
 *
 * - Find common bugs early in development with [`StrictMode`](https://react.dev/reference/react/StrictMode)
 * - Catch rendering errors and recover gracefully with an [error boundary](https://react.dev/reference/react/Component#catching-rendering-errors-with-an-error-boundary)
 *   TODO: Configure [`ErrorBoundary`](https://github.com/bvaughn/react-error-boundary#readme)
 * - Use a [suspense boundary](https://react.dev/reference/react/Suspense) to allow suspense features (such as `React.lazy`) to work.
 *   TODO: show a loading ("fallback") UI?
 */
export const Boundary = ({ children }: BoundaryProps) => (
  <StrictMode>
    <ErrorBoundary FallbackComponent={Fallback}>
      <Suspense>{children}</Suspense>
    </ErrorBoundary>
  </StrictMode>
);
