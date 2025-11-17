import { useContext } from 'react';
import invariant from 'tiny-invariant';

import { FooContext } from '#/react/contexts/FooContext';

export const useFoo = () => {
  const context = useContext(FooContext);

  invariant(
    context != null,
    '`useFoo` can only be used inside of a `FooContext.Provider`!'
  );

  return context;
};
