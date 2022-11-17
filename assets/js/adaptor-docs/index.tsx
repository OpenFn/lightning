import React from 'react';
import { createRoot } from 'react-dom/client';
import type Docs from './Docs';

interface Entrypoint {
  componentRoot: ReturnType<typeof createRoot> | null;
  destroyed(): void;
  el: HTMLElement;
  changeEvent: string;
  field?: HTMLTextAreaElement | null;
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

let DocsComponent: typeof Docs | undefined;

export default {
  mounted(this: Entrypoint) {
    import('./Docs').then(module => {
      DocsComponent = module.default as typeof Docs;
      this.componentRoot = createRoot(this.el);

      this.setupObserver();
      this.render();
    });
  },
  render() {
    const { adaptor } = this.el.dataset;
    if (DocsComponent) {
      this.componentRoot?.render(<DocsComponent adaptor={adaptor} />);
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
      attributeFilter: ['data-adaptor'],
      attributeOldValue: true,
    });
  },
  destroyed() {
    this.componentRoot?.unmount();
    this.observer?.disconnect();
  },
} as Entrypoint;
