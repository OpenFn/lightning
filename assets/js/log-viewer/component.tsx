import { editor as e } from 'monaco-editor';
import { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { useStore } from 'zustand';
import { useShallow } from 'zustand/react/shallow';

import { type Monaco, MonacoEditor } from '../monaco';

import { createLogStore } from './store';

export function mount(
  el: HTMLElement,
  store: ReturnType<typeof createLogStore>
) {
  const componentRoot = createRoot(el);

  componentRoot.render(<LogViewer logStore={store} />);

  function unmount() {
    return componentRoot.unmount();
  }

  return { unmount };
}

const LogViewer = ({
  logStore,
}: {
  logStore: ReturnType<typeof createLogStore>;
}) => {
  const stepId = useStore(logStore, state => state.stepId);
  const highlightedRanges = useStore(
    logStore,
    useShallow(state => state.highlightedRanges)
  );
  const formattedLogLines = useStore(
    logStore,
    useShallow(state => state.formattedLogLines)
  );

  const [monaco, setMonaco] = useState<Monaco>();
  const [editor, setEditor] = useState<e.IStandaloneCodeEditor>();

  const decorationsCollection = useRef<e.IEditorDecorationsCollection>();

  useEffect(() => {
    if (stepId && highlightedRanges.length > 0) {
      const firstLine = highlightedRanges[0].start;

      editor?.revealLineNearTop(firstLine);
    }
  }, [stepId]);

  useEffect(() => {
    if (monaco && editor) {
      const decorations = highlightedRanges.map(range => {
        return {
          range: new monaco.Range(range.start, 1, range.end, 1),
          options: {
            isWholeLine: true,
            linesDecorationsClassName: 'log-viewer-highlighted',
          },
        };
      });

      if (decorationsCollection.current) {
        decorationsCollection.current.set(decorations);
      } else {
        decorationsCollection.current =
          editor.createDecorationsCollection(decorations);
      }
    }
  }, [highlightedRanges, monaco, editor, formattedLogLines]);

  useEffect(() => {
    if (monaco) {
      // Define a language for our logs
      monaco.languages.register({ id: 'openFnLogs' });

      // Define a simple tokenizer for the language
      monaco.languages.setMonarchTokensProvider('openFnLogs', {
        tokenizer: {
          root: [[/^([A-Z\/]{2,4})/, 'logSource']],
        },
      });
    }
  }, [monaco]);

  return (
    <MonacoEditor
      defaultLanguage="openFnLogs"
      language="openFnLogs"
      theme="default"
      value={formattedLogLines}
      loading={<div>Loading...</div>}
      beforeMount={setMonaco}
      onMount={setEditor}
      options={{
        readOnly: true,
        scrollBeyondLastLine: false,
        fontFamily: 'Fira Code VF',
        fontSize: 14,
        fontLigatures: true,
        folding: false,
        fixedOverflowWidgets: true,
        minimap: {
          enabled: false,
        },
        wordWrap: 'on',
        lineNumbersMinChars: 3,
        automaticLayout: true,
      }}
    />
  );
};
