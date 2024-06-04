import type { editor as __MonacoEditor } from 'monaco-editor/esm/vs/editor/editor.api';
import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { useShallow } from 'zustand/react/shallow';
import { Monaco, MonacoEditor } from '../monaco';
import { LogLine, createLogStore } from './store';

function findLogIndicesByStepId(
  logs: LogLine[],
  stepId: string
): { first: number | null; last: number | null } {
  let firstIndex = logs.findIndex(log => log.step_id === stepId);
  let lastIndex = logs.findLastIndex(log => log.step_id === stepId);

  if (firstIndex === -1) {
    return { first: null, last: null };
  } else {
    return { first: firstIndex, last: lastIndex + 1 };
  }
}

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
  const stepId = logStore(state => state.stepId);
  const highlightedRanges = logStore(
    useShallow(state => state.highlightedRanges)
  );
  const formattedLogLines = logStore(
    useShallow(state => state.formattedLogLines)
  );

  const [monaco, setMonaco] = useState<Monaco | null>(null);
  const [editor, setEditor] =
    useState<__MonacoEditor.IStandaloneCodeEditor | null>(null);

  const decorationsCollection =
    useRef<__MonacoEditor.IEditorDecorationsCollection | null>(null);

  useEffect(() => {
    if (stepId && highlightedRanges.length > 0) {
      let firstLine = highlightedRanges[0].start;

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
      monaco!.languages.register({ id: 'openFnLogs' });

      // Define a simple tokenizer for the language
      monaco!.languages.setMonarchTokensProvider('openFnLogs', {
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
        minimap: {
          enabled: false,
        },
        wordWrap: 'on',
        lineNumbersMinChars: 3,
      }}
    />
  );
};
