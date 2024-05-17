import MonacoEditor, { Monaco } from '@monaco-editor/react';
import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';

export function mount(el: HTMLElement, dataclipId: string) {
  const componentRoot = createRoot(el);

  render(dataclipId);

  function render(dataclipId: string) {
    componentRoot.render(<EditorComponent dataclipId={dataclipId} />);
  }

  function unmount() {
    return componentRoot.unmount();
  }

  return { unmount, render };
}

function editorWillMount(monaco: typeof Monaco) {
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

const EditorComponent = ({ dataclipId }: { dataclipId: string }) => {
  const [content, setContent] = useState<string>('');
  const editorRef = useRef<any>(null);

  useEffect(() => {
    async function fetchDataclipContent() {
      // Commented out now because I cant get no-cache to work as expected. Using default cache for now.
      // Retrieve last modified timestamp from local storage if available
      // const lastModified = localStorage.getItem(`lastModified-${dataclipId}`);
      // const headers = new Headers();
      // // If a last modified date is present, append the 'If-Modified-Since' header
      // if (lastModified) {
      //   headers.append('If-Modified-Since', lastModified);
      // }

      try {
        const response = await fetch(`/dataclip/body/${dataclipId}`, {
          cache: 'default',
        });
        if (!response.ok && response.status !== 304) {
          throw new Error('Network response was not ok');
        }

        // Commented out now because I cant get no-cache to work as expected. Using default cache for now.
        // const newLastModified = response.headers.get('Last-Modified');
        // if (response.ok && newLastModified) {
        //   localStorage.setItem(`lastModified-${dataclipId}`, newLastModified);
        // }

        return await response.text();
      } catch (error) {
        console.error('Error fetching content:', error);
        return 'Failed to load content';
      }
    }

    fetchDataclipContent().then(fetchedContent => {
      setContent(fetchedContent);
    });
  }, [dataclipId]);

  return (
    <MonacoEditor
      defaultLanguage="json"
      theme="default"
      value={content}
      loading={<div>Loading...</div>}
      onMount={editor => (editorRef.current = editor)}
      beforeMount={editorWillMount}
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
