import React from 'react';
import { createRoot } from "react-dom/client";
import Editor from './Editor';

interface EditorEntrypoint {
  componentRoot: ReturnType<typeof createRoot> | null;
  mounted(): void;
  destroyed(): void;
  el: HTMLElement;
}

export default {
  mounted(this: EditorEntrypoint) {
    import('./Editor').then((module) => {
      const EditorComponent = module.default as typeof Editor;
      const form = this.el.children[0] as HTMLTextAreaElement;

      // Hide the default text box
      form.style.display = "none";

      // Insert a new div for the live editor
      const monaco = document.createElement("div");
      this.el.appendChild(monaco)
      this.componentRoot = createRoot(monaco);

      
      const handleChange = (src: string) => {
        if (form) {
          form.value = src
        }
      };

      const render = (source?: string) => {
        this.componentRoot?.render(
          <EditorComponent
            source={source}
            onChange={handleChange}
        />);
      };

      render(form.value);
    });
  },
  destroyed() {
    this.componentRoot?.unmount();
  },
} as EditorEntrypoint