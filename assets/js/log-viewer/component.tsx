import MonacoEditor, { Monaco } from '@monaco-editor/react';
import React, { useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { setTheme } from '../monaco';

export type LogLine = {
  id: string;
  message: string;
  source: string;
  level: string;
  step_id: string;
};

type LogMetadata = {
  id: string;
  source: string;
  step_id: string;
  line: number;
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
    componentRoot.render(
      <LogViewer
        logs={logs}
        runId={el.dataset.runId}
        stepId={el.dataset.stepId}
      />
    );
  }

  function unmount() {
    return componentRoot.unmount();
  }

  return { unmount, render };
}

const LogViewer = ({
  logs,
  stepId,
}: {
  logs: LogLine[];
  stepId: string | undefined;
}) => {
  // const [logs, setLogs] = useState<LogLine[]>([]);
  const monacoRef = useRef<Monaco | null>(null);
  const editorRef = useRef<any | null>(null);

  // window.addEventListener(`phx:logs-${runId}`, (event: CustomEvent) => {
  //   console.log('phx:logs', event.detail.logs);
  //   setLogs(logs.concat(event.detail.logs));
  // });

  const splitLogs = splitLogMessages(logs);

  const beforeMount = (monaco: Monaco) => {
    monacoRef.current = monaco;
    setTheme(monaco);
  };

  const onMount = (editor: any) => {
    editorRef.current = editor;
  };

  if (
    stepId !== undefined &&
    logs.length > 0 &&
    monacoRef.current !== null &&
    editorRef.current !== null
  ) {
    let monaco = monacoRef.current;
    let editor = editorRef.current;
    const { first, last } = findLogIndicesByStepId(splitLogs, stepId);
    if (first !== null && last !== null) {
      console.log('first', first, 'last', last);
      console.log('monaco editor', editor);
      console.log('monaco editor type', editor.getEditorType());

      const decos = editor.createDecorationsCollection([
        {
          range: new monaco.Range(first + 1, 1, last + 1, 1),
          options: {
            inlineClassName: 'bg-yellow-400 w-1 ml-0.5',
          },
        },
      ]);

      console.log('decos', decos);
      editor.revealLine(first + 1);
    }
  }

  return (
    <MonacoEditor
      defaultLanguage="plaintext"
      theme="default"
      value={logs.map(log => `${log.message}`).join('\n')}
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
        lineNumbersMinChars: 8,
        lineNumbers: originalLineNumber => {
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
