import { MonacoEditor, Monaco } from '../monaco';
import React, { useRef } from 'react';
import { createRoot } from 'react-dom/client';
import { createLogStore, LogLine } from './store';
import { useStore } from 'zustand';

function findLogIndicesByStepId(
  logs: LogLine[],
  stepId: string
): { first: number | null; last: number | null } {
  let first: number | null = null;
  let last: number | null = null;
  logs.forEach((log, index) => {
    if (log.step_id === stepId) {
      last = index;
      if (first === null) {
        first = index;
      }
    }
  });

  return { first, last };
}

export function mount(
  el: HTMLElement,
  store: ReturnType<typeof createLogStore>,
  stepId: string | undefined
) {
  const componentRoot = createRoot(el);

  componentRoot.render(<LogViewer el={el} store={store} stepId={stepId} />);

  function unmount() {
    return componentRoot.unmount();
  }

  return { unmount };
}

const LogViewer = ({
  el,
  store,
  stepId,
}: {
  el: HTMLElement;
  store: ReturnType<typeof createLogStore>;
  stepId: string | undefined;
}) => {
  const logs: LogLine[] = useStore(store, state => state.logLines);

  let decorationsCollection: any = null;
  const monacoRef = useRef<Monaco | null>(null);
  const editorRef = useRef<any | null>(null);

  el.addEventListener('log-viewer:highlight-step', (event: CustomEvent) => {
    stepId = event.detail.stepId;
    maybeHighlightStep();
  });

  const beforeMount = (monaco: Monaco) => {
    monacoRef.current = monaco;
  };

  const onMount = (editor: any) => {
    editorRef.current = editor;
    maybeHighlightStep();
  };

  function maybeHighlightStep() {
    // clear previous highlights
    decorationsCollection?.clear();

    if (stepId !== undefined && logs.length > 0) {
      let monaco = monacoRef.current;
      let editor = editorRef.current;
      const { first, last } = findLogIndicesByStepId(logs, stepId);
      if (first !== null && last !== null) {
        decorationsCollection = editor?.createDecorationsCollection([
          {
            range: new monaco.Range(first + 1, 1, last + 1, 1),
            options: {
              isWholeLine: true,
              linesDecorationsClassName: 'log-viewer-highlighted',
            },
          },
        ]);

        editor?.revealLineInCenter(first + 1);
      }
    }
  }

  return (
    <MonacoEditor
      defaultLanguage="plaintext"
      theme="default"
      value={logs.map(log => `(${log.source}) ${log.message}`).join('\n')}
      loading={<div>Loading...</div>}
      beforeMount={beforeMount}
      onMount={onMount}
      options={{
        readOnly: true,
        scrollBeyondLastLine: false,
        fontFamily: 'Fira Code VF',
        fontSize: 14,
        fontLigatures: true,
        minimap: {
          enabled: false,
        },
        wordWrap: 'on',
        lineNumbersMinChars: 3,
      }}
    />
  );
};
