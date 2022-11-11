// Hook for AdaptorDocs
// Dependencies are imported dynamically, saving loading Typescript
// and everything else until they are needed.

import type { mount } from './component';

interface AdaptorDocsComponentEntrypoint {
  component: ReturnType<typeof mount> | null;
  mounted(): void;
  destroyed(): void;
  el: HTMLElement;
  observer: MutationObserver | null;
}

export default {
  mounted(this: AdaptorDocsComponentEntrypoint) {
    // Detect changes to the `data-adaptor` attribute on the component.
    this.observer = new MutationObserver(mutations => {
      mutations.forEach(mutation => {
        if (
          mutation.type === 'attributes' &&
          mutation.attributeName == 'data-adaptor'
        ) {
          if (this.component) {
            this.component.update({
              specifier: (mutation.target as HTMLElement).dataset.adaptor,
            });
          }
        }
      });
    });

    this.observer.observe(this.el, { attributes: true });

    import('./component').then(({ mount }) => {
      this.component = mount(this.el, { specifier: this.el.dataset.adaptor });
    });
  },
  destroyed() {
    this.component?.unmount();
    this.observer?.disconnect();
  },
  component: null,
} as AdaptorDocsComponentEntrypoint;
