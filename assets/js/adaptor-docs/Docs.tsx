import React, { useCallback } from 'react';
import DocsPanel from './components/DocsPanel';

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
  return <DocsPanel specifier={adaptor} onInsert={handleInsert} />;
}