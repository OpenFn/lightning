import React from 'react';
import { createRoot } from 'react-dom/client';
import type Editor from './Editor';

import metadata_dhis2 from './metadata/dhis2.js'
import metadata_salesforce from './metadata/salesforce.js'

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
          metadata={metadata}
          onChange={src => this.handleContentChange(src)}
          disabled={disabled == "true"}
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
