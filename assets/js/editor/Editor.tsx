import React, { useState, useCallback, useEffect, useRef } from 'react';
import Monaco from '@monaco-editor/react';
import type { EditorProps as MonacoProps } from '@monaco-editor/react/lib/types';

import { fetchDTSListing, fetchFile } from '@openfn/describe-package';
import createCompletionProvider from './magic-completion';
import { initiateSaveAndRun } from '../common';

// static imports for core lib
import dts_es5 from './lib/es5.min.dts';

export const DEFAULT_TEXT =
  '// Get started by adding operations from the API reference\n';

type EditorProps = {
  source?: string;
  adaptor?: string; // fully specified adaptor name - <id>@<version>
  metadata?: object; // TODO I can actually this very effectively from adaptors...
  onChange?: (newSource: string) => void;
  disabled?: boolean;
};

const spinner = (
  <svg
    className="inline-block h-5 w-5 animate-spin"
    xmlns="http://www.w3.org/2000/svg"
    fill="none"
    viewBox="0 0 24 24"
  >
    <circle
      className="opacity-25"
      cx="12"
      cy="12"
      r="10"
      stroke="currentColor"
      strokeWidth="4"
    ></circle>
    <path
      className="opacity-75"
      fill="currentColor"
      d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
    ></path>
  </svg>
);

const loadingIndicator = (
  <div className="bg-vs-dark inline-block p-2">
    <span className="mr-2">Loading</span>
    {spinner}
  </div>
);

// https://microsoft.github.io/monaco-editor/api/interfaces/monaco.editor.IStandaloneEditorConstructionOptions.html
const defaultOptions: MonacoProps['options'] = {
  dragAndDrop: false,
  lineNumbersMinChars: 3,
  tabSize: 2,
  minimap: {
    enabled: false,
  },
  scrollBeyondLastLine: false,
  showFoldingControls: 'always',
  // automaticLayout: true, // TODO this may impact performance as it polls

  // Hide the right-hand "overview" ruler
  overviewRulerLanes: 0,
  overviewRulerBorder: false,

  codeLens: false,
  wordBasedSuggestions: false,

  suggest: {
    showKeywords: false,
    showModules: false, // hides global this
    showFiles: false, // This hides property names ??
    // showProperties: false, // seems to hide consts but show properties??
    showClasses: false,
    showInterfaces: false,
    showConstructors: false,
  },
};

type Lib = {
  content: string;
  filePath?: string;
};

async function loadDTS(
  specifier: string,
  type: 'namespace' | 'module' = 'namespace'
): Promise<Lib[]> {
  // Work out the module name from the specifier
  // (his gets a bit tricky with @openfn/ module names)
  const nameParts = specifier.split('@');
  nameParts.pop(); // remove the version
  const name = nameParts.join('@');

  const results: Lib[] = [
    {
      content: dts_es5,
    },
  ];
  if (name !== '@openfn/language-common') {
    const pkg = await fetchFile(`${specifier}/package.json`);
    const commonVersion = JSON.parse(pkg || '{}').dependencies?.[
      '@openfn/language-common'
    ];

    // jsDeliver doesn't appear to support semver range syntax (^1.0.0, 1.x, ~1.1.0)
    const commonVersionMatch = commonVersion?.match(/^\d+\.\d+\.\d+/);
    if (!commonVersionMatch) {
      console.warn(
        `@openfn/language-common@${commonVersion} contains semver range syntax.`
      );
    }

    const common = await loadDTS(
      `@openfn/language-common@${commonVersion.replace('^', '')}`,
      'module'
    );
    results.push(...common);
  }

  // Load all the DTS files and squash them into a single namespace
  // We seem to have to do this because Monaco doesn't recognise types declared in different files
  // across namespaces
  // This should work well enough on adaptors anyway
  let bigFile = '';
  for await (const filePath of fetchDTSListing(specifier)) {
    if (!filePath.startsWith('node_modules')) {
      let content = await fetchFile(`${specifier}${filePath}`);
      bigFile += content;
    }
  }
  results.push({
    content: `declare ${type} { ${bigFile} }`,
    filePath: `${name}$/types`,
  });

  return results;
}

export default function Editor({
  source,
  adaptor,
  onChange,
  disabled,
  metadata,
}: EditorProps) {
  const [lib, setLib] = useState<Lib[]>();
  const [loading, setLoading] = useState(false);
  const [monaco, setMonaco] = useState<typeof Monaco>();
  const [options, setOptions] = useState(defaultOptions);
  const listeners = useRef<{
    insertSnippet?: EventListenerOrEventListenerObject;
    updateLayout?: any;
  }>({});

  const handleSourceChange = useCallback(
    (newSource: string) => {
      if (onChange) {
        onChange(newSource);
      }
    },
    [onChange]
  );

  const handleEditorDidMount = useCallback(
    (editor: any, monaco: typeof Monaco) => {
      setMonaco(monaco);

      editor.addCommand(
        monaco.KeyCode.Escape,
        () => {
          document.activeElement.blur();
        },
        '!suggestWidgetVisible'
      );

      editor.addCommand(
        // https://microsoft.github.io/monaco-editor/typedoc/classes/KeyMod.html
        // https://microsoft.github.io/monaco-editor/typedoc/enums/KeyCode.html
        monaco.KeyMod.CtrlCmd | monaco.KeyCode.Enter,
        function () {
          const actionButton = document.getElementById('save-and-run')!;
          initiateSaveAndRun(actionButton);
        }
      );

      editor.addCommand(
        // https://microsoft.github.io/monaco-editor/typedoc/classes/KeyMod.html
        // https://microsoft.github.io/monaco-editor/typedoc/enums/KeyCode.html
        monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.Enter,
        function () {
          const actionButton = document.getElementById(
            'create-new-work-order'
          )!;
          initiateSaveAndRun(actionButton);
        }
      );

      monaco.languages.typescript.javascriptDefaults.setCompilerOptions({
        // This seems to be needed to track the modules in d.ts files
        allowNonTsExtensions: true,

        // Disables core js libs in code completion
        noLib: true,
      });

      listeners.current.insertSnippet = (e: Event) => {
        // Snippets are always added to the end of the job code
        const model = editor.getModel();
        const lastLine = model.getLineCount();
        const eol = model.getLineLength(lastLine);
        const op = {
          range: new monaco.Range(lastLine, eol, lastLine, eol),
          // @ts-ignore event typings
          text: `\n${e.snippet}`,
          forceMoveMarkers: true,
        };

        // Append the snippet
        // https://microsoft.github.io/monaco-editor/api/interfaces/monaco.editor.ICodeEditor.html#executeEdits
        editor.executeEdits('snippets', [op]);

        // Ensure the snippet is fully visible
        const newLastLine = model.getLineCount();
        editor.revealLines(lastLine + 1, newLastLine, 0); // 0 = smooth scroll

        // Set the selection to the start of the snippet
        editor.setSelection(new monaco.Range(lastLine + 1, 0, lastLine + 1, 0));

        // ensure the editor has focus
        editor.focus();
      };

      // Force the editor to resize
      listeners.current.updateLayout = (_e: Event) => {
        editor.layout({ width: 0, height: 0 });
        setTimeout(() => {
          try {
            editor.layout();
          } catch (e) {
            editor.layout();
          }
        }, 1);
      };

      document.addEventListener(
        'insert-snippet',
        listeners.current.insertSnippet
      );
      document.addEventListener(
        'update-layout',
        listeners.current.updateLayout
      );
    },
    []
  );

  useEffect(() => {
    if (monaco && metadata) {
      const p = monaco.languages.registerCompletionItemProvider(
        'javascript',
        createCompletionProvider(monaco, metadata)
      );
      return () => {
        // Note: For now, whenever the adaptor changes, the editor will be un-mounted and remounted, so this is safe
        // If and when the adaptor can be seamlessly changed, we'll have to be a bit smarter about how we dispose of the
        // completion handler. State doesn't work very well, we probably need a ref for this
        // If metadata is passed as a prop, this becomes a little bit easier to manage
        p.dispose();
      };
    }
  }, [monaco, metadata]);

  useEffect(() => {
    // Create a node to hold overflow widgets
    // This needs to be at the top level so that tooltips clip over Lightning UIs
    const overflowNode = document.createElement('div');
    overflowNode.className = 'monaco-editor widgets-overflow-container';
    document.body.appendChild(overflowNode);

    setOptions({
      ...defaultOptions,
      overflowWidgetsDomNode: overflowNode,
      fixedOverflowWidgets: true,
      readOnly: disabled,
    });

    return () => {
      overflowNode.parentNode?.removeChild(overflowNode);
      if (listeners.current?.insertSnippet) {
        document.removeEventListener(
          'insert-snippet',
          listeners.current.insertSnippet
        );
      }
    };
  }, []);

  useEffect(() => {
    if (adaptor) {
      setLoading(true);
      setLib([]); // instantly clear intelligence
      loadDTS(adaptor).then(l => {
        setLib(l);
        setLoading(false);
      });
    }
  }, [adaptor]);

  useEffect(() => {
    if (monaco) {
      monaco.languages.typescript.javascriptDefaults.setExtraLibs(lib);
    }
  }, [monaco, lib]);

  return (
    <>
      <div className="relative z-10 h-0 overflow-visible text-right text-xs text-white">
        {loading && loadingIndicator}
      </div>
      <Monaco
        defaultLanguage="javascript"
        theme="vs-dark"
        defaultPath="/job.js"
        value={source || DEFAULT_TEXT}
        options={options}
        onMount={handleEditorDidMount}
        onChange={handleSourceChange}
      />
    </>
  );
}
