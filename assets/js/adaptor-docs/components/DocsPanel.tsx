import React from 'react';
import type { PackageDescription } from '@openfn/describe-package';
import useDocs from '../hooks/useDocs';
import Function from './render/Function';

type DocsPanelProps = {
  specifier?: string;
  onInsert?: (text: string) => void;
};

const docsLink = (srcLink: string) => {
  return (
    <p>
      You can check the external docs site at
      <a
        className="text-indigo-400 underline underline-offset-2 hover:text-indigo-500 ml-2"
        href="https://docs.openfn.org/adaptors/#where-to-find-them"
        target="none"
      >
        docs.openfn.org/adaptors
      </a>{' '}
      or view the source code
      <a
        className="text-indigo-400 underline underline-offset-2 hover:text-indigo-500 ml-2"
        href={srcLink}
        target="none"
      >
        here
      </a>
      .
    </p>
  );
};

const DocsPanel = ({ specifier, onInsert }: DocsPanelProps) => {
  if (!specifier) {
    return <div>Nothing selected</div>;
  }

  const pkg = useDocs(specifier);

  if (pkg === null) {
    return <div className="block m-2">Loading docs...</div>;
  }
  if (pkg === false) {
    return (
      <div className="block m-2">
        <p>Sorry, an error occurred loading the docs for this adaptor.</p>
        {docsLink}
      </div>
    );
  }

  const { name, version, functions } = pkg as PackageDescription;
  const strippedName = name.replace(/^@openfn\/language-/, '');
  const srcLink = `https://github.com/OpenFn/adaptors/tree/%40openfn/language-${strippedName}%40${version}/packages/${strippedName}/src`;

  if (functions.length === 0) {
    return (
      <div className="block m-2">
        <h1 className="h1 text-lg font-bold text-secondary-700 mb-2">
          {name} ({version})
        </h1>
        <p>Sorry, docs are unavailable for this adaptor.</p>
        {docsLink(srcLink)}
      </div>
    );
  }

  return (
    <div className="block w-full overflow-auto ml-1">
      <h1 className="h1 text-lg font-bold text-secondary-700 mb-2 flex justify-between items-center">
        <span>
          {name} ({version})
        </span>
        <a
          className="text-xs text-indigo-400 underline underline-offset-2 hover:text-indigo-500 mx-2"
          target="none"
          href={srcLink}
        >
          view src
        </a>
      </h1>
      <div className="text-sm mb-4">
        These are the operations available for this adaptor:
      </div>
      {functions
        .sort((a, b) => {
          if (a.name > b.name) return 1;
          else if (a.name < b.name) return -1;
          return 0;
        })
        .map(fn => (
          <Function key={fn.name} fn={fn} onInsert={onInsert} />
        ))}
    </div>
  );
};

export default DocsPanel;
