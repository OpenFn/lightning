import React, { useRef, useCallback } from 'react';
import ResizeObserver from 'rc-resize-observer';
import Editor, { Monaco } from '@monaco-editor/react';
import type { editor } from 'monaco-editor';

export function setTheme(monaco: Monaco) {
  monaco.editor.defineTheme('default', {
    base: 'vs-dark',
    inherit: true,
    rules: [{ token: 'logSource', foreground: '#868686', fontStyle: 'italic' }],
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

export { Monaco };

export const MonacoEditor = ({
  onMount = (_editor: editor.IStandaloneCodeEditor, _monaco: Monaco) => {},
  ...props
}) => {
  const monacoRef = useRef<Monaco>();
  const editorRef = useRef<editor.IStandaloneCodeEditor>();

  const handleOnMount = useCallback((editor: any, monaco: Monaco) => {
    monacoRef.current = monaco;
    editorRef.current = editor;
    if (!props.options.enableCommandPalette) {
      const ctxKey = editor.createContextKey('command-palette-override', true);

      editor.addCommand(
        monaco.KeyCode.F1,
        () => {},
        'command-palette-override'
      );

      editor.onDidDispose(() => {
        ctxKey.reset();
      });
    }
    setTheme(monaco);
    onMount(editor, monaco);
  }, []);

  return (
    <ResizeObserver
      onResize={({ width, height }) => {
        if (width > 0 && height > 0) {
          // TODO maybe either debounce or track sizes
          editorRef.current?.layout({ width, height });
        }
      }}
    >
      <Editor onMount={handleOnMount} {...props} />
    </ResizeObserver>
  );
};
