import React from 'react';
import { createRoot } from 'react-dom/client';
import type JobEditor from './JobEditor';

// TODO needs reorganising
interface ViewHook {
  destroyed(): void;
  el: HTMLElement;
  pushEventTo(
    target: HTMLElement,
    event: string,
    payload: {},
    callback?: (reply: {}, ref: unknown) => void
  ): void;
  handleEvent(event: string, callback: (reply: {}) => void): unknown;
  removeHandleEvent(callbackRef: unknown): void;
  mounted(): void;
}


interface JobEditorEntrypoint extends ViewHook {
  componentRoot: ReturnType<typeof createRoot> | null;
  changeEvent: string;
  field?: HTMLTextAreaElement | null;
  handleContentChange(content: string): void;
  metadata?: object;
  observer: MutationObserver | null;
  render(): void;
  requestMetadata(): Promise<{}>;
  setupObserver(): void;
  removeHandleEvent(callbackRef: unknown): void;
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
      this.requestMetadata()
    });
  },
  handleContentChange(content: string) {
    this.pushEventTo(this.el, this.changeEvent, { source: content });
  },
  render() {
    const { adaptor, source, disabled } = this.el.dataset;
    if (JobEditorComponent) {
      this.componentRoot?.render(
        <JobEditorComponent
          adaptor={adaptor}
          source={source}
          metadata={this.metadata}
          disabled={Boolean(disabled)}
          onSourceChanged={src => this.handleContentChange(src)}
        />
      );
    }
  },
  requestMetadata() {
    return new Promise(resolve => {
      const callbackRef = this.handleEvent("metadata_ready", data => {
        console.log(data)
        this.removeHandleEvent(callbackRef);
        this.metadata = data
        resolve(data);
      });
      
      this.pushEventTo(this.el, 'request_metadata', {});
    });
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
