import React, { useState, useCallback, useEffect } from 'react';
import Monaco from "@monaco-editor/react";
import type { EditorProps as MonacoProps } from  "@monaco-editor/react/lib/types";

import { fetchDTSListing, fetchFile } from '@openfn/compiler';

type EditorProps = {
  source?: string;
  adaptorName: string;
  adaptorVersion: string;
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

async function loadDTS(adaptorName: string, adaptorVersion: string): Promise<Lib[]> {
  const results: Lib[] = [];
  const packagePath = `${adaptorName}@${adaptorVersion}`;
  for await (const fileName of fetchDTSListing(packagePath)) {
    if (!fileName.startsWith('node_modules')) {
      const f = await fetchFile(`${packagePath}${fileName}`)
      results.push({
        content: `declare module "${adaptorName}" { ${f} }`,
      });
    }
  }
  return results;
}

export default function Editor({ source, adaptorName, adaptorVersion, onChange }: EditorProps) {
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
    if (adaptorName) {
      loadDTS(adaptorName, adaptorVersion).then(l => setLib(l));
    }
  }, [adaptorName])

  useEffect(() => {
    if (monaco) {
      monaco.languages.typescript.javascriptDefaults.setExtraLibs(lib);
    }
  }, [monaco, lib]);
  
  return (<Monaco
    defaultLanguage="javascript"
    defaultValue="// loading..."
    value={source}
    options={options}
    beforeMount={handleEditorWillMount}
    onChange={handleSourceChange}
    // Styles to match tailwind, should these be passed in?
    height="24rem"
    className="rounded-md border border-secondary-300 shadow-sm overflow-hidden"
  />)
}
