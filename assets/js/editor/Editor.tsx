import React, { useCallback } from 'react';
import Monaco from "@monaco-editor/react";
import type { EditorProps as MonacoProps } from  "@monaco-editor/react/lib/types";

type EditorProps = {
  source?: string;
  onChange?: (newSource: string) => void;
}

// https://microsoft.github.io/monaco-editor/api/interfaces/monaco.editor.IStandaloneEditorConstructionOptions.html
const options: MonacoProps['options'] = {
  dragAndDrop: false,
  lineNumbersMinChars: 3,
  minimap: {
    enabled: false
  },
  codeLens: false,
};

// Using globals will let us defien top-level functions
// Note that we need to export here or else the file seems to be ignored
const dts = `
declare global {
  function fn(f: () => void): void;
  
  function each(path: string, operation: () => void): void;

  function combine(operation: () => void): void;
}

export default {};
`

export default function Editor({ source, onChange }: EditorProps) {
  const handleChange = useCallback((newSource: string) => {
    if (onChange) {
      onChange(newSource)
    }
  }, [onChange]);

  const handleEditorWillMount = useCallback((monaco: typeof Monaco) => {
    // TODO this typing is actually wrong?
    monaco.languages.typescript.javascriptDefaults.addExtraLib(dts);
    monaco.languages.typescript.typescriptDefaults.setCompilerOptions({
      // allowJs: true,
      // checkJs: true,
      // allowNonTsExtensions: true,
      noLib: true,
      // noresolve: true,
    });
  }, []);

  return (<Monaco
    height="300px"
    defaultLanguage="javascript"
    defaultValue="// loading..."
    value={source}
    options={options}
    beforeMount={handleEditorWillMount}
    onChange={handleChange}
  />)
}
