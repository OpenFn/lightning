import React from 'react';
import { createRoot } from 'react-dom/client';
import type Editor from './Editor';

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

interface EditorEntrypoint extends ViewHook {
  componentRoot: ReturnType<typeof createRoot> | null;
  changeEvent: string;
  field?: HTMLTextAreaElement | null;
  handleContentChange(content: string): void;
  requestMetadata(): Promise<{}>;
  observer: MutationObserver | null;
  render(): void;
  setupObserver(): void;
  loadMetadata(): Promise<object>;
  metadata: object | undefined;
}

type AttributeMutationRecord = MutationRecord & {
  attributeName: string;
  oldValue: string;
};

let EditorComponent: typeof Editor | undefined;

let metadata: object;

export default {
  // Temporary loading hook
  loadMetadata() {
    const { adaptor } = this.el.dataset;
    return new Promise(() => {
      // TODO what if the metadata changes in flight?
      // May need to double check the adaptor value
      if (adaptor) {
        if (adaptor.match('dhis2')) {
          metadata = metadata_dhis2;
        }
        else {
          metadata = metadata_salesforce;
        }
        this.render();
      } 
    });
  },
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
      this.loadMetadata();
    });

    // {error: 'no_credential' | 'no_adaptor' | 'no_matching_adaptor' | 'no_metadata_result' | 'invalid_json' }
    // or <the actual json from disk>
    this.requestMetadata().then(data => console.log(data));
  },
  handleContentChange(content: string) {
    this.pushEventTo(this.el, this.changeEvent, { source: content });
  },
  requestMetadata() {
    return new Promise(resolve => {
      let callbackRef: unknown;
      callbackRef = this.handleEvent("metadata_ready", data => {
        this.removeHandleEvent(callbackRef);
        resolve(data);
      });
      
      this.pushEventTo(this.el, 'request_metadata', {});
    });
  },
  render() {
    const { adaptor, source, disabled } = this.el.dataset;
    if (EditorComponent) {
      this.componentRoot?.render(
        <EditorComponent
          adaptor={adaptor}
          source={source}
          metadata={metadata}
          onChange={src => this.handleContentChange(src)}
          disabled={disabled == 'true'}
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
      attributeFilter: ['data-adaptor', 'data-change-event', 'data-disabled'],
      attributeOldValue: true,
    });
  },
  destroyed() {
    this.componentRoot?.unmount();
    this.observer?.disconnect();
  },
} as EditorEntrypoint;
