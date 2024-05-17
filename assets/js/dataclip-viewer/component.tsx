import React, { useEffect, useRef, useState } from 'react';
import MonacoEditor from '@monaco-editor/react';

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
      onMount={editor => (editorRef.current = editor)}
      options={{ readOnly: true }}
    />
  );
};

export default EditorComponent;
