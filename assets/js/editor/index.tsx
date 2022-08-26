import React from 'react';
import { createRoot } from "react-dom/client";
import Editor from './Editor';

interface EditorEntrypoint {
  componentRoot: ReturnType<typeof createRoot> | null;
  destroyed(): void;
  el: HTMLElement;
  field?: HTMLTextAreaElement | null;
  handleContentChange(content: string): void;
  mounted(): void;
  observer: MutationObserver | null;
  render(): void;
  setupObserver(): void;
}

let EditorComponent: typeof Editor | undefined;

export default {
  mounted(this: EditorEntrypoint) {
    import('./Editor').then((module) => {
      EditorComponent = module.default as typeof Editor;
      this.componentRoot = createRoot(this.el);

      const { hiddenInput } = this.el.dataset;
      if (hiddenInput) {
        this.field = document.getElementById(hiddenInput) as HTMLTextAreaElement || null
      } else {
        console.warn("Warning: no form binding found for editor. Content will not sync.")
      }
      this.setupObserver()
      this.render();
    });
  },
  handleContentChange(content: string) {
    if (this.field) {
      this.field.value = content
    }
  },
  render() {
    const { adaptor } = this.el.dataset;
    const source = this.field?.value ?? "";
    if (EditorComponent) {
      this.componentRoot?.render(
        <EditorComponent
          adaptor={adaptor}
          source={source}
          onChange={(src) => this.handleContentChange(src)}
      />);
    }
  },
  setupObserver() {
    this.observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (
          mutation.type === "attributes" &&
          mutation.attributeName == "data-adaptor"
        ) {
          this.render()
        }
      });
    });

    this.observer.observe(this.el, { attributes: true });
  },
  destroyed() {
    this.componentRoot?.unmount();
    this.observer?.disconnect();
  }
} as EditorEntrypoint