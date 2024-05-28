import { MonacoEditor, Monaco } from '../monaco';
import React, { useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';

export type LogLine = {
  id: string;
  message: string;
  source: string;
  level: string;
  step_id: string;
  timestamp: string;
};

// The VER logs are multiline
function splitLogMessages(logs: LogLine[]): LogLine[] {
  const newLogs: LogLine[] = [];

  logs.forEach(log => {
    // Split the message on every newline.
    const messages = log.message.split('\n');
    messages.forEach(message => {
      // Create a new log entry for each line, copying other attributes.
      newLogs.push({
        ...log,
        message: message,
      });
    });
  });

  return newLogs;
}

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

export function mount(el: HTMLElement) {
  const componentRoot = createRoot(el);

  render([]);

  function render(logs: LogLine[]) {
    if (el.dataset.runId === undefined) {
      throw new Error(
        'runId is missing from the element dataset. Ensure you have set data-run-id on the element.'
      );
    }
    componentRoot.render(<LogViewer logs={logs} hookEl={el} />);
  }

  function unmount() {
    return componentRoot.unmount();
  }

  return { unmount, render };
}

const LogViewer = ({
  logs,
  hookEl,
}: {
  logs: LogLine[];
  hookEl: HTMLElement;
}) => {
  // let runId = hookEl.dataset.runId;
  let stepId = hookEl.dataset.stepId;
  // let logs: LogLine[] = [];
  const splitLogs = splitLogMessages(logs);
  let decorationsCollection: any = null;
  const monacoRef = useRef<Monaco | null>(null);
  const editorRef = useRef<any | null>(null);

  // window.addEventListener(`phx:logs-${runId}`, (event: CustomEvent) => {
  //   const splitLogs = splitLogMessages(event.detail.logs);
  //   // console.log('splitLogs', splitLogs);
  //   logs = logs.concat(splitLogs);
  //   logs.sort(
  //     (a, b) =>
  //       new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
  //   );
  //   console.log('logs', logs);
  //   editorRef.current?.setValue(logs.map(log => `${log.message}`).join('\n'));
  //   maybeHighlightStep();
  // });

  hookEl.addEventListener('log-viewer:highlight-step', (event: CustomEvent) => {
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
      const { first, last } = findLogIndicesByStepId(splitLogs, stepId);
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
      value={logs.map(log => log.message).join('\n')}
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
        lineNumbersMinChars: 12,
        lineNumbers: (originalLineNumber: number) => {
          const log = splitLogs[originalLineNumber - 1];
          if (log) {
            return `${originalLineNumber} (${log.source})`;
          }
          return `${originalLineNumber}`;
        },
      }}
    />
  );
};
