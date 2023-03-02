import React from 'react';
import { createRoot } from 'react-dom/client';
import type Explorer from './Explorer';

// TODO try a single central metadata hook which shares information between components
import metadata_dhis2 from '../editor/metadata/dhis2.js'
import metadata_salesforce from '../editor/metadata/salesforce.js'

interface ExplorerEntryPoint {
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

let ExplorerComponent: typeof Explorer | undefined;

let metadata: object;

export default {
  // Temporary loading hook
  loadMetadata() {
    const { adaptor } = this.el.dataset;
    console.log(adaptor)
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
  mounted(this: ExplorerEntryPoint) {
    import('./Explorer').then(module => {
      ExplorerComponent = module.default as typeof Explorer;
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
    if (ExplorerComponent) {
      this.componentRoot?.render(
        <ExplorerComponent
          metadata={metadata}
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
} as ExplorerEntryPoint;
