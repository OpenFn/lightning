// Hook for Workflow Editor Component
import { PhoenixHook } from '../hooks/PhoenixHook';
import type { mount } from './component';
import {
  Patch,
  PendingAction,
  WorkflowProps,
  createWorkflowStore,
} from './store';

type WorkflowEditorEntrypoint = PhoenixHook<{
  _isMounting: boolean;
  _pendingWorker: Promise<void>;
  abortController: AbortController | null;
  component: ReturnType<typeof mount> | null;
  componentModule: Promise<{ mount: typeof mount }>;
  getWorkflowParams(): void;
  handleWorkflowParams(payload: { workflow_params: WorkflowProps }): void;
  maybeMountComponent(): void;
  onSelectionChange(id?: string): void;
  pendingChanges: PendingAction[];
  processPendingChanges(): void;
  pushPendingChange(
    pendingChange: PendingAction,
    abortController: AbortController
  ): Promise<boolean>;
  workflowStore: ReturnType<typeof createWorkflowStore>;
}>;

const createNewWorkflow = () => {
  const triggers = [
    {
      id: crypto.randomUUID(),
      type: 'webhook',
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
    console.debug('WorkflowEditor hook mounted');

    this._pendingWorker = Promise.resolve();
    this._isMounting = false;
    this.pendingChanges = [];

    // Setup our abort controller to stop any pending changes.
    this.abortController = new AbortController();

    // Preload the component
    this.componentModule = import('./component');

    this.workflowStore = createWorkflowStore({}, pendingChange => {
      this.pendingChanges.push(pendingChange);

      this.processPendingChanges();
    });

    this.handleEvent<{ workflow_params: WorkflowProps }>(
      'current-workflow-params',
      this.handleWorkflowParams.bind(this)
    );

    this.handleEvent('patches-applied', (response: { patches: Patch[] }) => {
      console.debug('patches-applied', response.patches);
      this.workflowStore.getState().applyPatches(response.patches);
    });

    this.handleEvent('navigate', (e: { href: string }) => {
      const id = new URL(e.href).searchParams.get('s');
      this.component?.render(id);
    });

    // Get the initial data from the server
    this.getWorkflowParams();
  },
  reconnected() {
    // TODO: request the workflow params, but this time create a diff
    // between the current state and the server state and send those diffs
    // to the server.
  },
  onSelectionChange(id?: string) {
    const currentUrl = new URL(window.location.href);
    const nextUrl = new URL(currentUrl);

    if (!id) {
      console.debug('Unselecting');

      nextUrl.searchParams.delete('s');
      nextUrl.searchParams.delete('m');
    } else {
      console.debug('Selecting', id);

      nextUrl.searchParams.set('s', id);
    }

    if (
      currentUrl.searchParams.toString() !== nextUrl.searchParams.toString()
    ) {
      this.liveSocket.pushHistoryPatch(nextUrl.toString(), 'push', this.el);
    }
  },
  destroyed() {
    if (this.component) {
      this.component.unmount();
    }

    if (this.abortController) {
      this.abortController.abort();
    }

    console.debug('WorkflowEditor destroyed');
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

          console.debug('push-change response', response);
          this.workflowStore.getState().applyPatches(response.patches);
          resolve(true);
        }
      );
    });
  },
  getWorkflowParams() {
    this.pushEventTo(this.el, 'get-initial-state', {});
  },
  handleWorkflowParams({ workflow_params: payload }) {
    this.workflowStore.setState(_state => payload);

    if (!payload.triggers.length && !payload.jobs.length) {
      // Create a placeholder chart and push it back up to the server
      const diff = createNewWorkflow();
      this.workflowStore.getState().add(diff);
    }

    this.maybeMountComponent();
  },
  maybeMountComponent() {
    if (!this._isMounting && !this.component) {
      this._isMounting = true;
      this.componentModule.then(({ mount }) => {
        this.component = mount(
          this.el,
          this.workflowStore,
          this.onSelectionChange.bind(this)
        );

        this._isMounting = false;
      });
    }
  },
} as WorkflowEditorEntrypoint;
