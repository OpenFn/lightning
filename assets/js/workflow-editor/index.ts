// Hook for Workflow Editor Component
import { mount } from './component';
import { WorkflowState, createWorkflowStore } from './store';
import { shallow } from 'zustand/shallow';

interface PhoenixHook {
  mounted(): void;
  el: HTMLElement;
  destroyed(): void;
  handleEvent<T = {}>(eventName: string, callback: (payload: T) => void): void;
  pushEventTo(
    selectorOrTarget: string | HTMLElement,
    event: string,
    payload: {},
    callback?: (reply: any, ref: any) => void
  ): void;
}

interface WorkflowEditorEntrypoint extends PhoenixHook {
  component: ReturnType<typeof mount> | null;
  workflowStore: ReturnType<typeof createWorkflowStore>;
  cancelStoreSubscription: () => void;
  sendChanges: (state: {}) => void;
}

export default {
  mounted(this: WorkflowEditorEntrypoint) {
    // add some defaults or pull from the DOM if needed
    this.workflowStore = createWorkflowStore({}, state =>
      this.sendChanges(state)
    );

    // What does the data look like coming from the server?
    this.handleEvent('data-changed', payload => {
      console.log('data-changed', payload);
      this.workflowStore.getState().setWorkflow(payload);
    });

    // We may want to subscribeWithSelector
    // https://github.com/pmndrs/zustand#using-subscribe-with-selector
    this.cancelStoreSubscription = this.workflowStore.subscribe(
      (state: WorkflowState, prevState: WorkflowState) => {
        if (
          state.jobs != prevState.jobs ||
          state.edges != prevState.edges ||
          state.triggers != prevState.triggers
        ) {
          const payload = {
            jobs: serialize(state.jobs),
            edges: serialize(state.edges),
            triggers: serialize(state.triggers),
          };

          if (prevState.workflow?.jobs) {
            console.log(
              'shallow comp jobs',
              shallow(payload.jobs, prevState.workflow.jobs)
            );
          }

          // this.sendChanges(state);
          console.log('nodes or edges changed');
        }

        console.log('state at subscribe', state, prevState);
      }
    );

    import('./component').then(({ mount }) => {
      this.pushEventTo(this.el, 'workflow-editor-mounted', {});
      this.component = mount(this.el, this.workflowStore);
    });
  },
  sendChanges(state: WorkflowState) {
    const payload = {
      jobs: serialize(state.jobs),
      edges: serialize(state.edges),
      triggers: serialize(state.triggers),
    };

    this.pushEventTo(this.el, 'update-workflow', payload);
  },
  destroyed() {
    this.cancelStoreSubscription();
    if (this.component) {
      this.component.unmount();
    }
  },
} as WorkflowEditorEntrypoint;

// Take the values of the object and remove the errors
function serialize(obj: Record<string, any>) {
  return Object.values(obj).map(({ errors, ...rest }) => rest);
}
