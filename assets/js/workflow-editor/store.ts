import { createStore } from 'zustand';
import { produce } from 'immer';

type WorkflowProps = {
  triggers: Record<string, any>;
  jobs: Record<string, any>;
  edges: Record<string, any>;
  workflow: any | null;
};

export interface WorkflowState extends WorkflowProps {
  addEdge: (edge: any) => void;
  addJob: (job: any) => void;
  addTrigger: (node: any) => void;
  setWorkflow: (payload: any) => void;
  onChange: (state: WorkflowState) => void;
}

function buildNode() {
  return { id: crypto.randomUUID() };
}

function buildEdge() {
  return { id: crypto.randomUUID() };
}

export const createWorkflowStore = (
  initProps?: Partial<WorkflowProps>,
  onChange?: (state: WorkflowState) => void
) => {
  const DEFAULT_PROPS: WorkflowProps = {
    triggers: {},
    jobs: {},
    edges: {},
    workflow: null,
  };

  return createStore<WorkflowState>()(set => ({
    ...DEFAULT_PROPS,
    ...initProps,
    addJob: job => {
      const newJob = buildNode();

      set(state =>
        produce(state, draft => {
          draft.jobs[newJob.id] = newJob;
        })
      );
    },
    addTrigger: trigger => {
      const newTrigger = buildNode();

      set(state =>
        produce(state, draft => {
          draft.triggers[newTrigger.id] = newTrigger;
        })
      );
    },
    addEdge: edge => {
      const newEdge = buildEdge();

      set(state =>
        produce(state, draft => {
          draft.edges[newEdge.id] = newEdge;
        })
      );
    },
    setWorkflow: payload => {
      console.log('payload', payload);

      set(state =>
        produce(state, draft => {
          for (const job of payload.jobs) {
            state.jobs[job.id] = job;
          }

          for (const trigger of payload.triggers) {
            state.triggers[trigger.id] = trigger;
          }

          for (const edge of payload.edges) {
            state.edges[edge.id] = edge;
          }

          state.workflow = payload;
        })
      );
    },
    onChange: onChange ? onChange : () => {},
  }));
};
