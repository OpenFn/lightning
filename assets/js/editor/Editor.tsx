import type { EditorProps as MonacoProps } from '@monaco-editor/react';
import { fetchDTSListing, fetchFile } from '@openfn/describe-package';
import type { editor } from 'monaco-editor';
import { useCallback, useEffect, useRef, useState } from 'react';

import { submitOrClick } from '../common';
import { MonacoEditor, type Monaco } from '../monaco';

import dts_es5 from './lib/es5.min.dts';
import createCompletionProvider from './magic-completion';

// static imports for core lib

export const DEFAULT_TEXT = `// Check out the Job Writing Guide for help getting started:
// https://docs.openfn.org/documentation/jobs/job-writing-guide
`;

type EditorProps = {
  source?: string;
  adaptor?: string; // fully specified adaptor name - <id>@<version>
  metadata?: object; // TODO I can actually this very effectively from adaptors...
  onChange?: (newSource: string) => void;
  disabled?: boolean;
  disabledMessage?: string;
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
  <div className="inline-block p-2">
    <span className="mr-2">Loading types</span>
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

  fontFamily: 'Fira Code VF',
  fontSize: 14,
  fontLigatures: true,

  suggest: {
    // https://microsoft.github.io/monaco-editor/docs.html#interfaces/editor.ISuggestOptions.html
    showModules: true,
    showKeywords: false,
    showFiles: false, // This hides property names ??
    // showProperties: false, // seems to hide consts but show properties??
    showClasses: false,
    showInterfaces: false,
    showConstructors: false,
    showDeprecated: false,
  },
};

type Lib = {
  content: string;
  filePath?: string;
};

async function loadDTS(specifier: string): Promise<Lib[]> {
  // Work out the module name from the specifier
  // (his gets a bit tricky with @openfn/ module names)
  const nameParts = specifier.split('@');
  nameParts.pop(); // remove the version
  const name = nameParts.join('@');

  const results: Lib[] = [{ content: dts_es5 }];

  // Load common into its own module
  // TODO maybe we need other dependencies too? collections?
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

    const commonSpecifier = `@openfn/language-common@${commonVersion.replace(
      '^',
      ''
    )}`;
    for await (const filePath of fetchDTSListing(commonSpecifier)) {
      if (!filePath.startsWith('node_modules')) {
        // Load every common typedef into the common module
        let content = await fetchFile(`${commonSpecifier}${filePath}`);
        content = content.replace(/\* +@(.+?)\*\//gs, '*/');
        results.push({
          content: `declare module '@openfn/language-common' { ${content} }`,
        });
      }
    }
  }

  // This will store types.d.ts, if we can find it
  let types = '';

  // This stores string content for our adaptor
  let adaptorDefs: string[] = [];

  for await (const filePath of fetchDTSListing(specifier)) {
    if (!filePath.startsWith('node_modules')) {
      let content = await fetchFile(`${specifier}${filePath}`);
      // Convert relative paths
      content = content
        .replace(/from '\.\//g, `from '${name}/`)
        .replace(/import '\.\//g, `import '${name}/`);

      // Remove js doc annotations
      // this regex means: find a * then an @ (with 1+ space in between), then match everything up to a closing comment */
      // content = content.replace(/\* +@(.+?)\*\//gs, '*/');

      const fileName = filePath.split('/').at(-1).replace('.d.ts', '');

      // Import the index as the global namespace - but take care to convert all paths to absolute
      if (fileName === 'index' || fileName === 'Adaptor') {
        // It turns out that "export * as " seems to straight up not work in Monaco
        // So this little hack will refactor import statements in a way that works
        content = content.replace(
          /export \* as (\w+) from '(.+)';/g,
          `

          import * as $1 from '$2';
          export { $1 };`
        );
        adaptorDefs.push(`declare namespace {
  {{$TYPES}} 
  ${content}
`);
      } else if (fileName === 'types') {
        types = content;
      } else {
        // Declare every other module as file
        adaptorDefs.push(`declare module '${name}/${fileName}' {
  {{$TYPES}}
  ${content}
}`);
      }
    }
  }

  // This just ensures that the global type defs appear in every scope
  // This is basically a hack to work around https://github.com/OpenFn/lightning/issues/2641
  // If we find a types.d.ts, append it to every other file
  adaptorDefs = adaptorDefs.map(def => def.replace('{{$TYPES}}', types));

  results.push(
    ...adaptorDefs.map(content => ({
      content,
    }))
  );

  return results;
}

export default function Editor({
  source,
  adaptor,
  onChange,
  disabled,
  disabledMessage,
  metadata,
}: EditorProps) {
  const [lib, setLib] = useState<Lib[]>();
  const [loading, setLoading] = useState(false);
  const [options, setOptions] = useState(defaultOptions);
  const listeners = useRef<{
    insertSnippet?: EventListenerOrEventListenerObject;
    updateLayout?: any;
  }>({});

  const [monaco, setMonaco] = useState<Monaco>();

  const handleSourceChange = useCallback(
    (newSource: string | undefined) => {
      if (onChange && newSource) {
        onChange(newSource);
      }
    },
    [onChange]
  );

  const handleEditorDidMount = useCallback(
    (editor: editor.IStandaloneCodeEditor, monaco: Monaco) => {
      window.monaco = monaco;
      setMonaco(monaco);

      editor.addCommand(
        monaco.KeyCode.Escape,
        () => {
          if (!(document.activeElement instanceof HTMLElement)) return;
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
          submitOrClick(actionButton);
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
          submitOrClick(actionButton);
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

      document.addEventListener(
        'insert-snippet',
        listeners.current.insertSnippet
      );
    },
    [lib]
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
    // Total hackage - acceptable given that the editor will be retired soon
    overflowNode.style.zIndex = '9999';
    document.body.appendChild(overflowNode);

    setOptions({
      ...defaultOptions,
      overflowWidgetsDomNode: overflowNode,
      fixedOverflowWidgets: true,
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
      loadDTS(adaptor)
        .then(l => {
          setLib(l);
        })
        .finally(() => {
          setLoading(false);
        });
    }
  }, [adaptor]);

  useEffect(() => {
    monaco?.languages.typescript.javascriptDefaults.setExtraLibs(lib!);
  }, [monaco, lib]);

  return (
    <>
      <div className="relative z-10 h-0 overflow-visible text-right text-xs text-white">
        {loading && loadingIndicator}
      </div>
      <MonacoEditor
        defaultLanguage="javascript"
        defaultPath="/job.js"
        loading={<div className="text-white">Loading...</div>}
        value={source || DEFAULT_TEXT}
        options={{
          ...options,
          readOnly: disabled,
          readOnlyMessage: {
            value: disabledMessage,
          },
          enableCommandPalette: true,
        }}
        onMount={handleEditorDidMount}
        onChange={handleSourceChange}
      />
    </>
  );
}
