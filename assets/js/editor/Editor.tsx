import React from 'react';
import Monaco from "@monaco-editor/react";

type EditorProps = {
  source?: string;
}

export default function Editor({ source }: EditorProps) {
  // return <h1>roll baby roll</h1>
  return (<Monaco
    height="300px"
    defaultLanguage="javascript"
    defaultValue="// loading..."
    value={source}
  />)
}
