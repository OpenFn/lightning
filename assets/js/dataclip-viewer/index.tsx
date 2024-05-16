import React from 'react';
import { createRoot } from 'react-dom/client';

const DataclipViewer = {
  root: null as ReturnType<typeof createRoot> | null,

  mounted() {
    const editorContainer = document.getElementById(this.el.dataset.target);
    if (editorContainer) {
      import('./component').then(({ default: EditorComponent }) => {
        this.root = createRoot(editorContainer);
        this.root.render(<EditorComponent dataclipId={this.el.dataset.id} />);
      });
    } else {
      console.error(
        `Failed to find monaco container with ID '${this.el.dataset.target}'`
      );
    }
  },

  updated() {
    if (this.root) {
      import('./component').then(({ default: EditorComponent }) => {
        this.root.render(<EditorComponent dataclipId={this.el.dataset.id} />);
      });
    }
  },

  destroyed() {
    if (this.root) {
      this.root.unmount();
    }
  },
};

export default DataclipViewer;
