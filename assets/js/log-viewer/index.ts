// index.tsx
import { PhoenixHook } from '../hooks/PhoenixHook';
import type { mount, LogLine } from './component';

type LogViewer = PhoenixHook<{
  component: ReturnType<typeof mount> | null;
  componentModule: Promise<{ mount: typeof mount }>;
  logLines: LogLine[];
}>;

export default {
  mounted(this: LogViewer) {
    this.logLines = [];
    this.componentModule = import('./component');

    this.componentModule.then(({ mount }) => {
      this.component = mount(this.el);
    });

    this.handleEvent(
      `logs-${this.el.dataset.runId}`,
      (event: { logs: LogLine[] }) => {
        console.log('Received logs', event.logs);
        this.logLines = this.logLines.concat(event.logs);
        this.logLines.sort(
          (a, b) =>
            new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
        );
        this.component?.render(this.logLines);
      }
    );
  },
  updated() {
    this.el.dispatchEvent(
      new CustomEvent('log-viewer:highlight-step', {
        detail: { stepId: this.el.dataset.stepId },
      })
    );
  },
  destroyed() {
    this.component?.unmount();
  },
} as LogViewer;
