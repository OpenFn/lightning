import React, { useState, useCallback, useEffect } from 'react';
import Monaco from "@monaco-editor/react";
import type { EditorProps as MonacoProps } from  "@monaco-editor/react/lib/types";

import { fetchDTSListing, fetchFile } from '@openfn/describe-package';

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
};

type Lib = {
  content: string;
}

// TODO this can take a little while to run, we should consider giving some feedback to the user
async function loadDTS(specifier: string): Promise<Lib[]> {
  // Work out the module name from the specifier
  // (his gets a bit tricky with @openfn/ module names)
  const nameParts = specifier.split('@')
  nameParts.pop() // remove the version
  const name = nameParts.join('@');

  const results: Lib[] = [];
  for await (const fileName of fetchDTSListing(specifier)) {
    if (!fileName.startsWith('node_modules')) {
      const f = await fetchFile(`${specifier}${fileName}`)
      results.push({
        content: `declare module "${name}" { ${f} }`,
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
  
  const handleEditorWillMount = useCallback((monaco: typeof Monaco) => {
    monaco.languages.typescript.javascriptDefaults.setCompilerOptions({
      // This seems to be needed to track the modules in d.ts files
      allowNonTsExtensions: true,
    });
    setMonaco(monaco);
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
    value={source || '// Write your code here'}
    options={options}
    beforeMount={handleEditorWillMount}
    onChange={handleSourceChange}
  />)
}
