import React, { useRef, useCallback } from 'react';
import ResizeObserver from 'rc-resize-observer';
import Editor, { Monaco } from '@monaco-editor/react';
import type { editor } from 'monaco-editor';

// import * as jsonWorker from 'monaco-editor/esm/vs/language/json/json.worker';
// import * as cssWorker from 'monaco-editor/esm/vs/language/css/css.worker';
// import * as htmlWorker from 'monaco-editor/esm/vs/language/html/html.worker';
// import * as tsWorker from 'monaco-editor/esm/vs/language/typescript/ts.worker';
// 'monaco-editor/esm/vs/editor/editor.worker'

const editorWorker = new Worker(
  new URL(
    'node_modules/monaco-editor/esm/vs/editor/editor.worker.js',
    import.meta.url
  ),
  { type: 'module' }
);

self.MonacoEnvironment = {
  getWorker(_, label) {
    console.log(label);

    // if (label === 'json') {
    //   return new jsonWorker();
    // }
    // if (label === 'css' || label === 'scss' || label === 'less') {
    //   return new cssWorker();
    // }
    // if (label === 'html' || label === 'handlebars' || label === 'razor') {
    //   return new htmlWorker();
    // }
    // if (label === 'typescript' || label === 'javascript') {
    //   return new tsWorker();
    // }
    // return new Worker(new URL('monaco-editor/esm/vs/editor/editor.worker', import.meta.url));

    return editorWorker;
  },
};
import * as monaco from 'monaco-editor';
import { loader } from '@monaco-editor/react';
loader.config({ monaco });

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
