import { useState, useEffect } from 'react';

import { useFoo } from '#/react/hooks/use-foo';

export const Baz = () => {
  const foo = useFoo();
  const [baz, setBaz] = useState(foo + 2);

  useEffect(() => {
    setBaz(foo + 2);
  }, [foo]);

  return <p>Baz: {baz}</p>;
};
