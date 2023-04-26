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
  pendingChanges: PendingAction[];
  pushPendingChange(
    pendingChange: PendingAction,
    abortController: AbortController
  ): Promise<boolean>;
  abortController: AbortController | null;
}

export default {
  mounted(this: WorkflowEditorEntrypoint) {
    this.pendingChanges = [];

    // Setup our abort controller to stop any pending changes.
    this.abortController = new AbortController();

    // Preload the component
    this.componentModule = import('./component');

    // Get the initial data from the server
    this.pushEventTo(this.el, 'get-initial-state', {}, (payload: any) => {
      this.workflowStore = createWorkflowStore(payload, pendingChange => {
        this.pendingChanges.push(pendingChange);

        // Ensure that changes are pushed in order
        // TODO: on the event of a change failing do we collect up all the
        // pending changes and revert them?
        (async () => {
          while (
            this.pendingChanges.length > 0 &&
            !this.abortController!.signal.aborted
          ) {
            const pendingChange = this.pendingChanges.shift()!;

            // TODO: if this fails or times out, we need to undo the change
            // Immer's patch callback also produces a list of inverse patches.
            await this.pushPendingChange(pendingChange, this.abortController!);
          }
        })();

        console.log('pendingChanges', this.pendingChanges);
      });

      this.componentModule.then(({ mount }) => {
        this.component = mount(this.el, this.workflowStore);
      });
    });
  },
  destroyed() {
    if (this.component) {
      this.component.unmount();
    }

    if (this.abortController) {
      this.abortController.abort();
    }
  },
  pushPendingChange(pendingChange, abortController?) {
    return new Promise((resolve, reject) => {
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
