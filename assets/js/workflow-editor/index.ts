// Hook for Workflow Editor Component
import type { PhoenixHook } from '../hooks/PhoenixHook';
import type { Lightning } from '../workflow-diagram/types';
import type { mount } from './component';
import {
  type Patch,
  type PendingAction,
  type WorkflowProps,
  createWorkflowStore,
} from './store';

export type WorkflowEditorEntrypoint = PhoenixHook<
  {
    _isMounting: boolean;
    _pendingWorker: Promise<void>;
    abortController: AbortController | null;
    component: ReturnType<typeof mount> | null;
    componentModule: Promise<{ mount: typeof mount }>;
    getWorkflowParams(): void;
    getItem(
      id?: string
    ): Lightning.TriggerNode | Lightning.JobNode | Lightning.Edge | undefined;
    handleWorkflowParams(payload: { workflow_params: WorkflowProps }): void;
    maybeMountComponent(): void;
    onSelectionChange(id?: string | null): void;
    pendingChanges: PendingAction[];
    processPendingChanges(): void;
    pushPendingChange(
      pendingChange: PendingAction,
      abortController: AbortController
    ): Promise<boolean>;
    workflowStore: ReturnType<typeof createWorkflowStore>;
    observer: MutationObserver | null;
    setupObserver(): void;
    hasLoaded: Promise<URL>;
  },
  { baseUrl?: string | undefined }
>;

// To support temporary workflow editor metrics submissions to Lightning
// server.
let workflowLoadParamsStart: number | null = null;

export default {
  mounted() {
    let setHasLoaded: (href: URL) => void;

    this.hasLoaded = new Promise(resolve => {
      setHasLoaded = resolve;
    });

    // Listen to navigation events, so we can update the base url that is used
    // to build urls to different nodes in the workflow.
    this.handleEvent<{ to: string; kind: string }>(
      'page-loading-stop',
      ({ to, kind }) => {
        if (kind === 'initial') setHasLoaded(new URL(to));
      }
    );

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

    this.handleEvent('set-disabled', (response: { disabled: boolean }) => {
      this.workflowStore.getState().setDisabled(response.disabled);
    });

    this.handleEvent<{ href: string; patch: boolean }>('navigate', e => {
      const id = new URL(window.location.href).searchParams.get('s');

      if (e.patch && this.component) this.component.render(id);
    });

    // Get the initial data from the server
    this.getWorkflowParams();
  },
  reconnected() {
    // TODO: request the workflow params, but this time create a diff
    // between the current state and the server state and send those diffs
    // to the server.
    console.log('reconnected', this.workflowStore.getState());
    this.pushEventTo(this.el, 'get-current-state', {}, response => {
      console.log('get-current-state response', response);
      this.workflowStore.getState().rebase(response['workflow_params']);
    });
  },
  getItem(
    id?: string
  ): Lightning.TriggerNode | Lightning.JobNode | Lightning.Edge | undefined {
    if (id) {
      const { jobs, triggers, edges } = this.workflowStore.getState();
      const everything = [...jobs, ...triggers, ...edges];
      for (const i of everything) {
        if (id === i.id) {
          return i;
        }
      }
    }
  },
  onSelectionChange(id?: string) {
    (async () => {
      console.debug('onSelectionChange', id);

      await this.hasLoaded;
      const currentUrl = new URL(window.location.href);
      const nextUrl = new URL(currentUrl);

      const idExists = this.getItem(id);
      if (!idExists) {
        nextUrl.searchParams.delete('s');
        nextUrl.searchParams.delete('m');
        nextUrl.searchParams.set('placeholder', 'true');
      } else {
        nextUrl.searchParams.delete('placeholder');
        if (!id) {
          console.debug('Unselecting');

          nextUrl.searchParams.delete('s');
          nextUrl.searchParams.delete('m');
        } else {
          console.debug('Selecting', id);

          nextUrl.searchParams.set('s', id);
        }
      }

      if (
        currentUrl.searchParams.toString() !== nextUrl.searchParams.toString()
      ) {
        // This looks awkward, but is at least a public API
        this.liveSocket.execJS(
          this.el,
          '[["patch",{"replace":false,"href":"' + nextUrl.toString() + '"}]]'
        );
      }
    })();
  },
  destroyed() {
    this.component?.unmount();
    this.abortController?.abort();
    this.observer?.disconnect();

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
  pushPendingChange(
    pendingChange: PendingAction,
    abortController: AbortController
  ): Promise<boolean> {
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
    let start = new Date();
    workflowLoadParamsStart = start.getTime();
    console.debug('get-initial-state pushed', start.toISOString());
    console.time('workflow-params load');
    this.pushEventTo(this.el, 'get-initial-state', {});
  },
  handleWorkflowParams({
    workflow_params: payload,
  }: {
    workflow_params: WorkflowProps;
  }) {
    this.workflowStore.setState(_state => payload);

    this.maybeMountComponent();
    let end = new Date();
    console.debug('current-worflow-params processed', new Date().toISOString());
    console.timeEnd('workflow-params load');
    this.pushEventTo(this.el, 'workflow_editor_metrics_report', {
      metrics: [
        {
          event: 'workflow-params load',
          start: workflowLoadParamsStart,
          end: end.getTime(),
        },
      ],
    });
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
