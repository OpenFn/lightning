import { PhoenixHook } from '../hooks/PhoenixHook';
import { useLogStore, LogLine } from './store'; // Import the store
import { mount } from './component';

type LogViewer = PhoenixHook<{
  component: ReturnType<typeof mount> | null;
}>;

export default {
  mounted(this: LogViewer) {
    this.component = mount(this.el);

    this.handleEvent(
      `logs-${this.el.dataset.runId}`,
      (event: { logs: LogLine[] }) => {
        console.log('Received logs', event.logs);
        useLogStore.getState().addLogLines(event.logs);
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
