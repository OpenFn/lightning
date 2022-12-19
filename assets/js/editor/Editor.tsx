import React, { useState, useCallback, useEffect } from 'react';
import Monaco from "@monaco-editor/react";
import type { EditorProps as MonacoProps } from  "@monaco-editor/react/lib/types";

import { fetchDTSListing, fetchFile } from '@openfn/describe-package';

const DEFAULT_TEXT = '// Get started by adding operations from the API reference';

type EditorProps = {
  source?: string;
  adaptor?: string; // fully specified adaptor name - <id>@<version>
  onChange?: (newSource: string) => void;
}

// https://microsoft.github.io/monaco-editor/api/interfaces/monaco.editor.IStandaloneEditorConstructionOptions.html
const options: MonacoProps['options'] = {
  dragAndDrop: false,
  lineNumbersMinChars: 3,
  minimap: {
    enabled: false
  },
  scrollBeyondLastLine: false,
  showFoldingControls: 'always',
  
  // Hide the right-hand "overview" ruler
  overviewRulerLanes: 0,
  overviewRulerBorder: false,

  codeLens: false,
  wordBasedSuggestions: false,

  suggest: {
    showKeywords: false,
  }
};

type Lib = {
  content: string;
  filePath: string;
}

// TODO this can take a little while to run, we should consider giving some feedback to the user
async function loadDTS(specifier: string): Promise<Lib[]> {
  // Work out the module name from the specifier
  // (his gets a bit tricky with @openfn/ module names)
  const nameParts = specifier.split('@')
  nameParts.pop() // remove the version
  const name = nameParts.join('@');

  const results: Lib[] = [];
  for await (const filePath of fetchDTSListing(specifier)) {
    if (!filePath.startsWith('node_modules')) {
      const content = await fetchFile(`${specifier}${filePath}`)
      results.push({
        content: `declare namespace "${name}" { ${content} }`,
        filePath
      });
    }
  }
  return results;
}

export default function Editor({ source, adaptor, onChange }: EditorProps) {
  const [lib, setLib] = useState<Lib[]>();
  const [monaco, setMonaco] = useState<typeof Monaco>();

  const handleSourceChange = useCallback((newSource: string) => {
    if (onChange) {
      onChange(newSource)
    }
  }, [onChange]);
  
  const handleEditorDidMount = useCallback((editor: any, monaco: typeof Monaco) => {
    setMonaco(monaco);

    monaco.languages.typescript.javascriptDefaults.setCompilerOptions({
      // This seems to be needed to track the modules in d.ts files
      allowNonTsExtensions: true,

      // Disables core js libs in code completion
      noLib: true,
    });

    const handleInsertSnippet = (e: Event) => {
      // Snippets are always added to the end of the job code
      const model = editor.getModel()
      const lastLine = model.getLineCount();
      const eol = model.getLineLength(lastLine)
      const op = {
        // TODO need to be in the end col...
        range: new monaco.Range(lastLine, eol, lastLine, eol),
        // @ts-ignore event typings
        text: `\n${e.snippet}`,
        forceMoveMarkers: true
      };
      
      // Append the snippet
      // https://microsoft.github.io/monaco-editor/api/interfaces/monaco.editor.ICodeEditor.html#executeEdits
      editor.executeEdits("snippets", [op]);

      // Ensure the snippet is fully visible
      const newLastLine = editor.model.getLineCount();
      editor.revealLines(lastLine + 1, newLastLine, 0) // 0 = smooth scroll

      // Set the selection to the start of the snippet
      editor.setSelection(new monaco.Range(lastLine+1, 0, lastLine+1, 0));
      
      // ensure the editor has focus
      editor.focus();
    }

    document.addEventListener('insert-snippet', handleInsertSnippet)
    
    return () => {
      document.removeEventListener(handleInsertSnippet);
     }
  }, []);

  
  useEffect(() => {
    if (adaptor) {
      setLib([]); // instantly clear intelligence
      loadDTS(adaptor).then(l => setLib(l));
    }
  }, [adaptor])

  useEffect(() => {
    if (monaco) {
      monaco.languages.typescript.javascriptDefaults.setExtraLibs(lib);
    }
  }, [monaco, lib]);
  
  return (<Monaco
    defaultLanguage="javascript"
    loading=""
    theme="vs-dark"
    value={source || DEFAULT_TEXT}
    options={options}
    onMount={handleEditorDidMount}
    onChange={handleSourceChange}
  />)
}
