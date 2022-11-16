import React, { useCallback } from 'react';
import Docs from '@openfn/adaptor-docs';

type DocsProps = {
  adaptor: string; // name of the adaptor to load. aka specfier.
}

export default ({ adaptor }: DocsProps) => {
  const handleInsert = useCallback((text: string) => {
    const e = new Event('insert-snippet');
    // @ts-ignore
    e.snippet = text;
    document.dispatchEvent(e);
  }, []);
  return <Docs specifier={adaptor} onInsert={handleInsert} />;
}

// export default ({ adaptor }: DocsProps) => {
//   const [d] = useState(adaptor);
//   return <h1>{d}</h1>
// }