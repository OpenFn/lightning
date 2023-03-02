import React from 'react';
import { createRoot } from 'react-dom/client';
import type Explorer from './Explorer';

import loadMetadata from '../metadata-loader/metadata';

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
  metadata: object | undefined;
}

type AttributeMutationRecord = MutationRecord & {
  attributeName: string;
  oldValue: string;
};

let ExplorerComponent: typeof Explorer | undefined;

export default {
  mounted(this: ExplorerEntryPoint) {
    import('./Explorer').then(module => {
      ExplorerComponent = module.default as typeof Explorer;
      this.componentRoot = createRoot(this.el);

      const { changeEvent, adaptor } = this.el.dataset;
      if (changeEvent) {
        this.changeEvent = changeEvent;
      } else {
        console.warn('Warning: No changeEvent set. Content will not sync.');
      }
      this.setupObserver();
      this.render();
      loadMetadata(adaptor).then((m) => {
        this.metadata = m;
        this.render();
      });
    });
  },
  handleContentChange(content: string) {
    this.pushEventTo(this.el, this.changeEvent, { source: content });
  },
  render() {
    if (ExplorerComponent) {
      this.componentRoot?.render(
        <ExplorerComponent
          metadata={this.metadata}
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
          if (attributeName === 'adaptor') {
            loadMetadata(newValue!).then((m) => {
              this.metadata = m;
              this.render();
            });
          } else {
            this.render();
          }
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
