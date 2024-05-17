import MonacoEditor, { Monaco } from '@monaco-editor/react';
import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { setTheme } from '../monaco';

export function mount(el: HTMLElement, dataclipId: string) {
  const componentRoot = createRoot(el);

  render(dataclipId);

  function render(dataclipId: string) {
    componentRoot.render(<DataclipViewer dataclipId={dataclipId} />);
  }

  function unmount() {
    return componentRoot.unmount();
  }

  return { unmount, render };
}

async function fetchDataclipContent(dataclipId: string) {
  try {
    const response = await fetch(`/dataclip/body/${dataclipId}`, {
      cache: 'default',
    });
    if (!response.ok && response.status !== 304) {
      throw new Error('Network response was not ok');
    }

    return await response.text();
  } catch (error) {
    console.error('Error fetching content:', error);
    return 'Failed to load content';
  }
}

const DataclipViewer = ({ dataclipId }: { dataclipId: string }) => {
  const [content, setContent] = useState<string>('');
  const monacoRef = useRef<Monaco | null>(null);

  const beforeMount = (monaco: Monaco) => {
    monacoRef.current = monaco;
    setTheme(monaco);
  };

  useEffect(() => {
    fetchDataclipContent(dataclipId).then(setContent)
  }, [dataclipId]);

  return (
    <MonacoEditor
      defaultLanguage="json"
      theme="default"
      value={content}
      loading={<div>Loading...</div>}
      beforeMount={beforeMount}
      options={{
        readOnly: true,
        lineNumbersMinChars: 3,
        tabSize: 2,
        scrollBeyondLastLine: false,
        overviewRulerLanes: 0,
        overviewRulerBorder: false,
        fontFamily: 'Fira Code VF',
        fontSize: 14,
        fontLigatures: true,
      }}
    />
  );
};
