import React from 'react';

/**
 * [Lazily](https://react.dev/reference/react/lazy) load the component when it
 * is first rendered.
 */
export const lazyLoadComponent = <const Props = object>(
  factory: () => Promise<React.ComponentType<Props>>,
  displayName?: string
) => {
  const Lazy = React.lazy(async () => ({ default: await factory() }));

  if (displayName) {
    // @ts-expect-error -- Incorrect upstream type
    Lazy.displayName = displayName;
  }

  return Lazy;
};
