import React, { useEffect, useRef, useState } from 'react';
import MonacoEditor from '@monaco-editor/react';

const EditorComponent = ({ dataclipId }: { dataclipId: string }) => {
  const [content, setContent] = useState<string>('');
  const editorRef = useRef<any>(null);

  useEffect(() => {
    async function fetchDataclipContent() {
      try {
        const response = await fetch(`/dataclip/body/${dataclipId}`);
        if (!response.ok) throw new Error('Network response was not ok');
        return await response.text();
      } catch (error) {
        console.error('Error fetching content:', error);
        return 'Failed to load content';
      }
    }

    fetchDataclipContent().then(fetchedContent => {
      setContent(fetchedContent);
      if (editorRef.current) {
        editorRef.current.setValue(fetchedContent);
      }
    });
  }, [dataclipId]);

  return (
    <MonacoEditor
      defaultLanguage="json"
      theme="vs-dark"
      value={content}
      height="100%"
      onMount={editor => (editorRef.current = editor)}
      options={{ readOnly: true }}
    />
  );
};

export default EditorComponent;
