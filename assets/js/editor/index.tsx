import React from 'react';
import { createRoot } from "react-dom/client";
import Editor from './Editor';

interface EditorEntrypoint {
  componentRoot: ReturnType<typeof createRoot> | null;
  mounted(): void;
  destroyed(): void;
  render(source: string): void;
  handleEvent(name: string, fn: () => void): void;
  el: HTMLElement;
  liveSocket: any;
  observer: MutationObserver;
}

export default {
  mounted(this: EditorEntrypoint) {
    import('./Editor').then((module) => {
      const EditorComponent = module.default as typeof Editor;
      this.componentRoot = createRoot(this.el);

      const render = (source?: string) => {
        this.componentRoot?.render(<EditorComponent source={source} />);
      };

      render(this.el.dataset.source);

      // Detect changes to the `data-source` attribute on the component.
      this.observer = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
          if (
            mutation.type === "attributes" &&
            mutation.attributeName == "data-source"
          ) {
            console.log('**')
            render((mutation.target as HTMLElement).dataset.source)
          }
        });
      });

      this.observer.observe(this.el, { attributes: true });

    });
  },
  destroyed() {
    this.componentRoot?.unmount();
    this.observer?.disconnect();
  },
} as EditorEntrypoint