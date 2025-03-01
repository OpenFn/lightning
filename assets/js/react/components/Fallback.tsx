import type { FallbackProps } from 'react-error-boundary';

export type { FallbackProps };

export const Fallback = ({ error }: FallbackProps) => (
  <div role="alert">
    <p>Something went wrong:</p>
    <pre style={{ color: 'red' }}>{error.message}</pre>
  </div>
);
