import { useState, useEffect } from 'react';

import { useFoo } from '#/react/hooks/use-foo';

export const Bar = () => {
  const foo = useFoo();
  const [bar, setBar] = useState(0);

  useEffect(() => {
    setBar(foo + 1);
  }, [foo]);

  return <p>Bar: {bar}</p>;
};
