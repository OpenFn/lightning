import { useState, useEffect } from 'react';

import { useFoo } from '#/react/hooks/use-foo';

export type BarProps = {
  children?: React.ReactNode;
};

export const Bar = ({ children }: BarProps) => {
  const foo = useFoo();
  const [bar, setBar] = useState(foo + 1);

  useEffect(() => {
    setBar(foo + 1);
  }, [foo]);

  const [showChildren, setShowChildren] = useState(true);

  return (
    <>
      <p>Bar: {bar}</p>
      <label>
        <input
          type="checkbox"
          checked={showChildren}
          onChange={() => setShowChildren(show => !show)}
        />
        Show children?
      </label>
      {showChildren && children}
    </>
  );
};
