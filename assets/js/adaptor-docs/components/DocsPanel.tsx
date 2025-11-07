import type { PackageDescription } from '@openfn/describe-package';
import { useCallback } from 'react';

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
        <a className="link ml-2" href={srcLink} target="_blank">
          github.com/OpenFn/adaptors
        </a>
      </div>
    </div>
  );
};

const EditorHelp = () => (
  <details className="mb-4">
    <summary className="text-sm cursor-pointer">
      <h3 className="inline">Editor tips & shortcuts</h3>
    </summary>
    <div className="text-sm border-solid border-grey-300 border-l-4 pl-2 mt-2">
      <p className="mb-2">
        Most adaptors provide intelligent code suggestions to the editor. Start
        typing and press TAB or ENTER to accept a suggestion, or ESC to cancel
      </p>
      <ul className="list-disc ml-4">
        <li>Press CTRL+SPACE to show suggestions</li>
        <li>
          Press CTRL+SPACE again to toggle suggestion details (recommended!)
        </li>
        <li>Press F1 to show the command menu (not all commands will work!)</li>
      </ul>
    </div>
  </details>
);

const DocsPanel = ({ specifier, onInsert }: DocsPanelProps) => {
  if (!specifier) {
    return <div>Nothing selected</div>;
  }

  const pkg = useDocs(specifier);

  if (pkg === null) {
    return (
      <div className="block w-full overflow-auto ml-1">Loading docs...</div>
    );
  }
  if (pkg === false) {
    return (
      <>
        <div className="block w-full overflow-auto ml-1 mt-1">
          <p className="mt-2">
            An error occurred loading the docs for this adaptor.
          </p>
          <DocsLink specifier={specifier} />
        </div>
      </>
    );
  }

  const { name, version, functions } = pkg;

  if (functions.length === 0) {
    return (
      <div className="block w-full overflow-auto ml-1 mt-1">
        <h1 className="h1 text-lg font-bold text-secondary-700 mb-2">
          {name} ({version})
        </h1>
        <p className="mt-2">Docs are unavailable for this adaptor.</p>
        <DocsLink specifier={specifier} />
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
      <EditorHelp />
      <h3>Adaptor API</h3>
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
