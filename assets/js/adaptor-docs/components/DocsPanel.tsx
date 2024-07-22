import React, { useCallback } from 'react';
import type { PackageDescription } from '@openfn/describe-package';
import useDocs from '../hooks/useDocs';
import Function from './render/Function';

type DocsPanelProps = {
  specifier?: string;
  onInsert?: (text: string) => void;
};

const DocsLink = ({ specifier }: { specifier: string }) => {
  const { name, version } = useCallback(() => {
    const strippedName = specifier.replace(/^@openfn\/language-/, '');
    const [name, version] = strippedName.split('@');
    return { name, version };
  }, [specifier])();

  const srcLink = `https://github.com/OpenFn/adaptors/tree/%40openfn/language-${name}%40${version}/packages/${name}/src`;

  return (
    <div className="mb-2 text-sm">
      <div>
        External docs:
        <a
          className="link ml-2"
          href={`https://docs.openfn.org/adaptors/packages/${name}-docs`}
          target="_blank"
        >
          docs.openfn.org
        </a>
      </div>
      <div>
        Source code:
        <a
          className="link ml-2"
          href={srcLink}
          target="_blank"
        >
          github.com/OpenFn/adaptors
        </a>
      </div>
    </div>
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
      <>
        <DocsLink specifier={specifier} />
        <div className="block m-2">
          <p>An error occurred loading the docs for this adaptor.</p>
        </div>
      </>
    );
  }

  const { name, version, functions } = pkg as PackageDescription;

  if (functions.length === 0) {
    return (
      <div className="block m-2">
        <h1 className="h1 text-lg font-bold text-secondary-700 mb-2">
          {name} ({version})
        </h1>
        <DocsLink specifier={specifier} />
        <p>Docs are unavailable for this adaptor.</p>
      </div>
    );
  }

  return (
    <div className="block w-full overflow-auto ml-1">
      <h1 className="h1 text-lg font-bold text-secondary-700 mb-2 flex justify-between items-center">
        <span>
          {name} ({version})
        </span>
      </h1>
      <DocsLink specifier={specifier} />
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
