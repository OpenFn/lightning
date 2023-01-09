// Hook for Workflow Diagram Component
// `component.jsx` is imported dynamically, saving loading React
// and all the other dependencies until they are needed.
import type { mount } from './component';
import { WebhookTrigger } from './src/types';

interface WorkflowDiagramEntrypoint {
  el: HTMLElement;
  component: ReturnType<typeof mount> | null;
  baseUrl: URL;
  observer: MutationObserver | null;
  projectSpace: {} | null;
  mounted(): void;
  destroyed(): void;
  handleEvent(
    eventName: string,
    callback: () => (e: string, b: boolean) => void
  ): any;
  setupObserver(): void;
  updateProjectSpace(): void;
  addJob(upstreamId: string): void;
  selectJob(id: string): void;
  selectWorkflow(id: string): void;
  copyWebhookUrl(webhookUrl: string): void;
  unselectNode(): void;
}

type AttributeMutationRecord = MutationRecord & {
  attributeName: string;
  oldValue: string;
};

export default {
  mounted(this: WorkflowDiagramEntrypoint) {
    const basePath = this.el.getAttribute('base-path');
    if (!basePath) {
      throw new Error('Workflow Diagram expects a `base-path` attribute.');
    }
    this.baseUrl = new URL(basePath, window.location.origin);

    import('./component').then(({ mount }) => {
      this.component = mount(this.el);

      this.setupObserver();

      if (!this.component) {
        throw new Error('Component not set.');
      }

      const projectSpace = this.updateProjectSpace();

      this.component.update({
        onJobAddClick: node => {
          this.addJob(node.data.id);
        },
        onNodeClick: (event, node) => {
          switch (node.type) {
            case 'trigger':
              if (node.data.trigger.type === 'webhook') {
                this.copyWebhookUrl(node.data.trigger.webhookUrl);
              }
              break;
            case 'job':
              this.selectJob(node.data.id);
              break;

            case 'workflow':
              this.selectWorkflow(node.data.id);
              break;
          }
        },
        onPaneClick: _event => {
          this.unselectNode();
        },
      });
    });
  },
  destroyed() {
    console.debug('Unmounting WorkflowDiagram component');

    this.observer?.disconnect();
    this.component?.unmount();
  },
  setupObserver() {
    this.observer = new MutationObserver(mutations => {
      mutations.forEach(mutation => {
        const { attributeName, oldValue } = mutation as AttributeMutationRecord;
        const newValue = this.el.getAttribute(attributeName);
        if (oldValue !== newValue) {
          this.updateProjectSpace();
        }
      });
    });

    this.observer.observe(this.el, {
      attributeFilter: ['data-project-space'],
      attributeOldValue: true,
    });
  },
  updateProjectSpace() {
    const decoded = JSON.parse(atob(this.el.dataset.projectSpace));
    this.component!.setProjectSpace(decoded);

    return decoded;
  },
  // Add `j/new?upstream_id=<id>` to the URL.
  addJob(upstreamId: string) {
    const addJobUrl = new URL(this.baseUrl);
    addJobUrl.pathname += '/j/new';
    addJobUrl.search = new URLSearchParams({
      upstream_id: upstreamId,
    }).toString();
    this.liveSocket.pushHistoryPatch(addJobUrl.toString(), 'push', this.el);
  },
  // Add `j/<id>` to the URL.
  selectJob(id: string) {
    const selectJobUrl = new URL(this.baseUrl);
    selectJobUrl.pathname += `/j/${id}`;
    this.liveSocket.pushHistoryPatch(selectJobUrl.toString(), 'push', this.el);
  },
  // Add `w/<id>` to the URL.
  selectWorkflow(id: string) {
    const selectWorkflowUrl = new URL(this.baseUrl);
    //selectWorkflowUrl.pathname = `/w/${id}`;
    this.liveSocket.pushHistoryPatch(
      selectWorkflowUrl.toString(),
      'push',
      this.el
    );
  },
  copyWebhookUrl(webhookUrl: string) {
    navigator.clipboard.writeText(webhookUrl);
    this.pushEvent('copied-to-clipboard', {});
  },
  // Remove `?selected=<id>` from the URL.
  unselectNode() {
    this.liveSocket.pushHistoryPatch(this.baseUrl.toString(), 'push', this.el);
  },
} as WorkflowDiagramEntrypoint;
