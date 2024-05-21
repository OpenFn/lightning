// index.tsx
import { PhoenixHook } from '../hooks/PhoenixHook';
import type { mount, LogLine } from './component';

type LogViewer = PhoenixHook<{
  component: ReturnType<typeof mount> | null;
  componentModule: Promise<{ mount: typeof mount }>;
}>;

export default {
  mounted(this: LogViewer) {
    this.componentModule = import('./component');

    this.componentModule.then(({ mount }) => {
      this.component = mount(this.el);
    });
  },
  updated() {
    this.el.dispatchEvent(
      new CustomEvent('log-viewer:updated', {
        detail: { stepId: this.el.dataset.stepId },
      })
    );
  },
  destroyed() {
    this.component?.unmount();
  },
} as LogViewer;
