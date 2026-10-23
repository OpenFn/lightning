import Editor, { loader, type Monaco } from '@monaco-editor/react';
import { setUpMonaco } from '@openfn/ui';
import type { editor } from 'monaco-editor';
import * as monaco from 'monaco-editor';
import { useCallback } from 'react';

// Configure Monaco with ESM workers
// This needs to be outside of the component to ensure it's only set once
if (typeof window !== 'undefined') {
  // @ts-ignore - Monaco global configuration
  window.MonacoEnvironment = {
    getWorker(_moduleId: string, label: string) {
      switch (label) {
        case 'json':
          return new Worker(new URL('json.worker.js', import.meta.url), {
            type: 'module',
          });
        case 'css':
          return new Worker(new URL('css.worker.js', import.meta.url), {
            type: 'module',
          });
        case 'html':
          return new Worker(new URL('html.worker.js', import.meta.url), {
            type: 'module',
          });
        case 'typescript':
        case 'javascript':
          return new Worker(new URL('typescript.worker.js', import.meta.url), {
            type: 'module',
          });
        default:
          return new Worker(new URL('editor.worker.js', import.meta.url), {
            type: 'module',
          });
      }
    },
  };
}

loader.config({ monaco });

// The theme and the openFnLogs language come from the design system, so its
// editors and Lightning's look the same.
export function setTheme(monaco: Monaco) {
  setUpMonaco(monaco);
  monaco.editor.setTheme('default');
}

export type { Monaco };

export const MonacoEditor = ({
  onMount = (_editor: editor.IStandaloneCodeEditor, _monaco: Monaco) => {},
  ...props
}) => {
  const handleOnMount = useCallback((editor: any, monaco: Monaco) => {
    if (!props['options']?.enableCommandPalette) {
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

  return <Editor onMount={handleOnMount} {...props} />;
};
