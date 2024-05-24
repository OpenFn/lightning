import React, { useRef, useCallback } from 'react';
import ResizeObserver from 'rc-resize-observer';
import Editor, { Monaco } from '@monaco-editor/react';

export function setTheme(monaco: Monaco) {
  monaco.editor.defineTheme('default', {
    base: 'vs-dark',
    inherit: true,
    rules: [],
    colors: {
      'editor.foreground': '#E2E8F0',
      'editor.background': '#334155', // slate-700
      'editor.lineHighlightBackground': '#475569', // slate-600
      'editor.selectionBackground': '#4f5b66',
      'editorCursor.foreground': '#c0c5ce',
      'editorWhitespace.foreground': '#65737e',
      'editorIndentGuide.background': '#65737F',
      'editorIndentGuide.activeBackground': '#FBC95A',
    },
  });
  monaco.editor.setTheme('default');
}

export { Monaco }

export const MonacoEditor = ({ onMount = (editor: any, monaco: Monaco) => {}, ...props}) => {
  const monacoRef = useRef<any>(null);

  const handleOnMount = useCallback((editor: any, monaco: Monaco) => {
    monacoRef.current = monaco;
    setTheme(monaco);
    onMount(editor, monaco)
  }, []);

  return (
    <ResizeObserver
        onResize={({width, height}) => {
          // TODO maybe either debounce or track sizes 
          monacoRef.current?.editor.layout({width, height: height});
        }}
      >
      <Editor onMount={handleOnMount} {...props} />
   </ResizeObserver>)
}