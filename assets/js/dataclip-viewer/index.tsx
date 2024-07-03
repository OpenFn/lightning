import { PhoenixHook } from '../hooks/PhoenixHook';
import type { mount } from './component';

type DataclipViewer = PhoenixHook<
  {
    component: ReturnType<typeof mount> | null;
    componentModule: Promise<{ mount: typeof mount }>;
  },
  { target: string; id: string }
>;

export default {
  mounted(this: DataclipViewer) {
    const editorContainer = document.getElementById(this.el.dataset.target);
    this.componentModule = import('./component.js');

    if (editorContainer) {
      this.componentModule.then(({ mount }) => {
        this.component = mount(editorContainer, this.el.dataset.id);
      });
    } else {
      console.error(
        `Failed to find monaco container with ID '${this.el.dataset.target}'`
      );
    }
  },

  updated() {
    this.component?.render(this.el.dataset.id);
  },

  destroyed() {
    this.component?.unmount();
  },
} as DataclipViewer;
