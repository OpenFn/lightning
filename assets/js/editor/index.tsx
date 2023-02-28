import React from 'react';
import { createRoot } from 'react-dom/client';
import type Editor from './Editor';

interface EditorEntrypoint {
  componentRoot: ReturnType<typeof createRoot> | null;
  destroyed(): void;
  el: HTMLElement;
  changeEvent: string;
  field?: HTMLTextAreaElement | null;
  handleContentChange(content: string): void;
  pushEventTo(target: HTMLElement, event: string, payload: {}): void;
  mounted(): void;
  observer: MutationObserver | null;
  render(): void;
  setupObserver(): void;
}

type AttributeMutationRecord = MutationRecord & {
  attributeName: string;
  oldValue: string;
};

let EditorComponent: typeof Editor | undefined;

export default {
  mounted(this: EditorEntrypoint) {
    import('./Editor').then(module => {
      EditorComponent = module.default as typeof Editor;
      this.componentRoot = createRoot(this.el);

      const { changeEvent } = this.el.dataset;
      if (changeEvent) {
        this.changeEvent = changeEvent;
      } else {
        console.warn('Warning: No changeEvent set. Content will not sync.');
      }
      this.setupObserver();
      this.render();
    });
  },
  handleContentChange(content: string) {
    this.pushEventTo(this.el, this.changeEvent, { source: content });
  },
  render() {
    const { adaptor, source, disabled } = this.el.dataset;
    if (EditorComponent) {
      this.componentRoot?.render(
        <EditorComponent
          adaptor={adaptor}
          source={source}
          onChange={src => this.handleContentChange(src)}
          disabled={disabled}
        />
      );
    }
  },
  setupObserver() {
    this.observer = new MutationObserver(mutations => {
      mutations.forEach(mutation => {
        const { attributeName, oldValue } = mutation as AttributeMutationRecord;
        const newValue = this.el.getAttribute(attributeName);
        if (oldValue !== newValue) {
          this.render();
        }
      });
    });

    this.observer.observe(this.el, {
      attributeFilter: ['data-adaptor', 'data-change-event'],
      attributeOldValue: true,
    });
  },
  destroyed() {
    this.componentRoot?.unmount();
    this.observer?.disconnect();
  },
} as EditorEntrypoint;
