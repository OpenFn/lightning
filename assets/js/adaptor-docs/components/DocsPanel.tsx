import React from 'react';
import type { PackageDescription } from '@openfn/describe-package';
import useDocs from '../hooks/useDocs';
import Function from './render/Function';

type DocsPanelProps = {
  specifier?: string;
  onInsert?: (text: string) => void;
}

const DocsPanel = ({ specifier, onInsert }: DocsPanelProps) => {
  if (!specifier) {;
    return <div>Nothing selected</div>;
  }

  const pkg = useDocs(specifier);
  if (pkg === null) {
    return <div>Loading...</div>
  }
  if (pkg === false) {
    return <div>Failed to load docs.</div>
  }
  
  const { name, version, functions } = pkg as PackageDescription;
  return (
    <div className="block m-2">
      <h1 className="h1 text-lg font-bold text-secondary-700 mb-2">{name} ({version})</h1>
      <div className="text-sm mb-4">These are the operations available for this adaptor:</div>
      {functions
        .sort((a, b) => {
          if (a.name > b.name) return 1;
          else if (a.name < b.name) return -1;
          return 0;
        })
        .map((fn) => <Function key={fn.name} fn={fn} onInsert={onInsert} />)}
    </div>
    );
};

export default DocsPanel;