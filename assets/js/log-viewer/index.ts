// index.tsx
import { PhoenixHook } from '../hooks/PhoenixHook';
import type { mount, LogLine } from './component';

type LogViewer = PhoenixHook<{
  component: ReturnType<typeof mount> | null;
  componentModule: Promise<{ mount: typeof mount }>;
  logs: LogLine[];
}>;

export default {
  mounted(this: LogViewer) {
    this.logs = [];
    this.componentModule = import('./component');

    this.componentModule.then(({ mount }) => {
      this.component = mount(this.el);

      this.handleEvent(`logs-${this.el.dataset.runId}`, event => {
        this.logs = this.logs.concat(event.logs);
        this.component?.render(this.logs);
      });
    });
  },

  destroyed() {
    this.component?.unmount();
  },
} as LogViewer;
