import React, { useState, useEffect } from 'react';
import Monaco from "@monaco-editor/react";
import type { EditorProps as MonacoProps } from  "@monaco-editor/react/lib/types";

type EditorProps = {
  source?: string;
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

let libContent=`
type noCodeSuggestionType =
    "noCodeSuggestion1" |
    "noCodeSuggestion2"

interface interfaceA {
    no_code_suggestion?: noCodeSuggestionType
}

interface interfaceB {
    interface_a?: interfaceA
}

interface TEST {
    find_by(attrs: interfaceB): void
    find_by_b(attrs: noCodeSuggestionType): void
}

declare var $test: TEST
`


const dts = `
declare module 'jam' {
  export declare function test(): void;
}

declare global {
  function wibble(x: string): string;
  
  function each(path: string, operation: () => void): void;
}

export type whatever = string;


declare var hello = "world";
`

export default function Editor({ source }: EditorProps) {
  const handleEditorWillMount = (monaco: typeof Monaco) => {
    console.log('loading libs')
    console.log(monaco)
    // TODO this typing is actually wrong?
    monaco.languages.typescript.typescriptDefaults.addExtraLib(dts);
    //monaco.languages.typescript.typescriptDefaults.addExtraLib(dts, 'file://node_modules/jam.d.ts');
    // monaco.languages.typescript.typescriptDefaults.setExtraLibs([{
    //   content: dts
    // }]);
    monaco.languages.typescript.typescriptDefaults.setCompilerOptions({
      allowJs: true,
      checkJs: true,
      allowNonTsExtensions: true,
      noLib: true,
      noresolve: true,
    });
  }

  return (<Monaco
    height="300px"
    defaultLanguage="typescript"
    defaultValue="// loading..."
    value={source}
    options={options}
    beforeMount={handleEditorWillMount}
  />)
}
