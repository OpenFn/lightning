// Hook for Workflow Editor Component
import type { mount } from './component';
import { Patch, PendingAction, createWorkflowStore } from './store';

interface PhoenixHook {
  mounted(): void;
  el: HTMLElement;
  destroyed(): void;
  handleEvent<T = {}>(eventName: string, callback: (payload: T) => void): void;
  pushEventTo<P = {}, R = any>(
    selectorOrTarget: string | HTMLElement,
    event: string,
    payload: P,
    callback?: (reply: R, ref: any) => void
  ): void;
}

interface WorkflowEditorEntrypoint extends PhoenixHook {
  component: ReturnType<typeof mount> | null;
  workflowStore: ReturnType<typeof createWorkflowStore>;
  componentModule: Promise<{ mount: typeof mount }>;
  _pendingWorker: Promise<void>;
  pendingChanges: PendingAction[];
  processPendingChanges(): void;
  pushPendingChange(
    pendingChange: PendingAction,
    abortController: AbortController
  ): Promise<boolean>;
  abortController: AbortController | null;
  editJobUrl: string;
  editTriggerUrl: string;
  selectJob(id: string): void;
  selectTrigger(id: string): void;
  unselectNode(): void;
  onSelectionChange(id?: string): void;
}

const createNewWorkflow = () => {
  const triggers = [
    {
      id: crypto.randomUUID(),
    },
  ];
  const jobs = [
    {
      id: crypto.randomUUID(),
    },
  ];
  const edges = [
    {
      id: crypto.randomUUID(),
      source_trigger_id: triggers[0].id,
      target_job_id: jobs[0].id,
    },
  ];
  return { triggers, jobs, edges };
};

export default {
  mounted(this: WorkflowEditorEntrypoint) {
    this._pendingWorker = Promise.resolve();
    // TODO: ensure that this is set
    this.editJobUrl = this.el.dataset.editJobUrl!;
    this.editTriggerUrl = this.el.dataset.editTriggerUrl!;
    this.pendingChanges = [];

    // Setup our abort controller to stop any pending changes.
    this.abortController = new AbortController();

    // Preload the component
    this.componentModule = import('./component');

    this.handleEvent('patches-applied', (response: { patches: Patch[] }) => {
      console.debug('patches-applied', response.patches);
      this.workflowStore.getState().applyPatches(response.patches);
    });

    // Get the initial data from the server
    this.pushEventTo(this.el, 'get-initial-state', {}, (payload: any) => {
      this.workflowStore = createWorkflowStore(
        { ...payload, editJobUrl: this.editJobUrl },
        pendingChange => {
          this.pendingChanges.push(pendingChange);

          this.processPendingChanges();
        }
      );

      if (!payload.triggers.length && !payload.jobs.length) {
        // Create a placeholder chart and push it back up to the server
        const diff = createNewWorkflow();
        this.workflowStore.getState().add(diff);
      }

      this.componentModule.then(({ mount }) => {
        this.component = mount(
          this.el,
          this.workflowStore,
          this.onSelectionChange.bind(this)
        );
        this.component.render(this.workflowStore.getState());
      });
    });
  },
  selectJob(id: string) {
    const url = this.editJobUrl.replace(':job_id', id);
    this.liveSocket.pushHistoryPatch(url, 'push', this.el);
  },
  selectTrigger(id: string) {
    const url = this.editTriggerUrl.replace(':trigger_id', id);
    this.liveSocket.pushHistoryPatch(url, 'push', this.el);
  },
  unselectNode() {
    this.liveSocket.pushHistoryPatch('/', 'push', this.el.dataset.baseUrl!);
  },
  onSelectionChange(id?: string) {
    if (!id) {
      this.unselectNode();
      return;
    }

    const type = Object.entries(this.workflowStore.getState()).find(
      ([_type, nodes]) => {
        return nodes.find(node => node.id === id);
      }
    )?.[0];

    switch (type) {
      case 'jobs':
        this.selectJob(id);
        break;
      case 'triggers':
        this.selectTrigger(id);
        break;
      case undefined:
        throw new Error(`Can't find node for id: ${id}`);
      default:
        throw new Error(`Unknown type ${type}`);
    }
  },
  destroyed() {
    if (this.component) {
      this.component.unmount();
    }

    if (this.abortController) {
      this.abortController.abort();
    }
  },
  processPendingChanges() {
    // Ensure that changes are pushed in order
    // TODO: on the event of a change failing do we collect up all the
    // pending changes and revert them?
    this._pendingWorker = this._pendingWorker.then(async () => {
      while (
        this.pendingChanges.length > 0 &&
        !this.abortController!.signal.aborted
      ) {
        const pendingChange = this.pendingChanges.shift()!;

        // TODO: if this fails or times out, we need to undo the change
        // Immer's patch callback also produces a list of inverse patches.
        await this.pushPendingChange(pendingChange, this.abortController!);
      }
    });
  },
  pushPendingChange(pendingChange, abortController?) {
    return new Promise((resolve, reject) => {
      console.debug('pushing change', pendingChange);
      // How do we _undo_ the change if it fails?
      this.pushEventTo<PendingAction, { patches: Patch[] }>(
        this.el,
        'push-change',
        pendingChange,
        response => {
          abortController?.signal.addEventListener('abort', () =>
            reject(false)
          );

          this.workflowStore.getState().applyPatches(response.patches);
          resolve(true);
        }
      );
    });
  },
} as WorkflowEditorEntrypoint;
