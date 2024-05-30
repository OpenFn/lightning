import { PhoenixHook } from '../hooks/PhoenixHook';
import { useLogStore, LogLine } from './store';
import { mount } from './component';

type LogViewer = PhoenixHook<{
  component: ReturnType<typeof mount> | null;
  viewerEl: HTMLElement | null;
  loadingEl: HTMLElement | null;
}>;

export default {
  mounted(this: LogViewer) {
    const viewerId = this.el.dataset.viewerEl;
    const loadingId = this.el.dataset.loadingEl;

    if (!viewerId || !loadingId) {
      throw new Error('Viewer or loading element data attributes are not set');
    }

    this.viewerEl = document.getElementById(viewerId);
    this.loadingEl = document.getElementById(loadingId);

    if (!this.viewerEl || !this.loadingEl) {
      throw new Error('Viewer or loading element not found');
    }

    this.component = mount(this.viewerEl, this.el.dataset.stepId);

    this.handleEvent(
      `logs-${this.el.dataset.runId}`,
      (event: { logs: LogLine[] }) => {
        if (this.loadingEl && this.viewerEl) {
          this.loadingEl.style.display = 'none';
          this.viewerEl.style.display = 'block';
        }
        useLogStore.getState().addLogLines(event.logs);
      }
    );
  },

  updated() {
    this.viewerEl?.dispatchEvent(
      new CustomEvent('log-viewer:highlight-step', {
        detail: { stepId: this.el.dataset.stepId },
      })
    );
  },

  destroyed() {
    this.component?.unmount();
  },
} as LogViewer;
