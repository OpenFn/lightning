import React, { useEffect, useRef, useState } from 'react';
import MonacoEditor from '@monaco-editor/react';
import { createRoot } from 'react-dom/client';

// Define the React component for handling the editor
const EditorComponent = ({ dataclipId }: { dataclipId: string }) => {
  const [content, setContent] = useState<string>('');
  const editorRef = useRef<any>(null);

  useEffect(() => {
    const fetchDataclipContent = async () => {
      try {
        const response = await fetch(`/dataclip/body/${dataclipId}`);
        if (!response.ok) throw new Error('Network response was not ok');
        return await response.text();
      } catch (error) {
        console.error('Error fetching content:', error);
        return 'Failed to load content';
      }
    };

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
      onMount={editor => {
        editorRef.current = editor;
      }}
      options={{ readOnly: true }}
    />
  );
};

// Phoenix Hook setup
const DataclipViewer = {
  root: null as ReturnType<typeof createRoot> | null,

  mounted() {
    this.root = createRoot(this.el);
    this.root.render(<EditorComponent dataclipId={this.el.dataset.id} />);
  },

  updated() {
    if (this.root) {
      this.root.render(<EditorComponent dataclipId={this.el.dataset.id} />);
    }
  },

  destroyed() {
    if (this.root) {
      this.root.unmount();
    }
  },
};

export default DataclipViewer;
