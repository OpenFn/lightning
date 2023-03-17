import React from 'react';
import { createRoot } from 'react-dom/client';
import type JobEditor from './JobEditor';

interface JobEditorEntrypoint {
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

let JobEditorComponent: typeof JobEditor | undefined;


export default {

  mounted(this: JobEditorEntrypoint) {
    import('./JobEditor').then(module => {
      JobEditorComponent = module.default as typeof JobEditor;
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
    const { adaptor, source } = this.el.dataset;
    if (JobEditorComponent) {
      this.componentRoot?.render(
        <JobEditorComponent
          adaptor={adaptor}
          source={source}
          onSourceChanged={src => this.handleContentChange(src)}
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
} as JobEditorEntrypoint;
