import React from 'react';
import { createRoot } from 'react-dom/client';
import type JobEditor from './JobEditor';
import { sortMetadata } from '../metadata-loader/metadata';

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
  metadata?: true | object;
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
    console.group('JobEditor');
    console.debug('Mounted');
    import('./JobEditor').then(module => {
      console.group('JobEditor');
      console.debug('loaded module');
      console.groupEnd();
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
      this.requestMetadata().then(() => this.render());
    });

    console.groupEnd();
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
          disabled={disabled === 'true'}
          onSourceChanged={src => this.handleContentChange(src)}
        />
      );
    }
  },
  requestMetadata() {
    this.metadata = true; // indicate we're loading
    this.render();
    return new Promise(resolve => {
      const callbackRef = this.handleEvent('metadata_ready', data => {
        this.removeHandleEvent(callbackRef);
        const sortedMetadata = sortMetadata(data);
        this.metadata = sortedMetadata;
        resolve(sortedMetadata);
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
