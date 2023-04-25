import { applyPatches, enablePatches, produce } from 'immer';
import { createStore } from 'zustand';
import type { Patch as ImmerPatch } from 'immer';

enablePatches();

type WorkflowProps = {
  triggers: {}[];
  jobs: {}[];
  edges: {}[];
  workflow: any | null;
  change_id: string | null;
};

export interface WorkflowState extends WorkflowProps {
  addEdge: (edge: any) => void;
  addJob: (job: any) => void;
  addTrigger: (node: any) => void;
  setWorkflow: (payload: any) => void;
  onChange: (pendingAction: PendingAction) => void;
  applyPatches: (patches: Patch[]) => void;
}

// Immer's Patch type has an array of strings for the path, but RFC 6902
// specifies that the path should be a string. This is a workaround.
export type Patch = {
  path: string;
} & Omit<ImmerPatch, 'path'>;

export interface PendingAction {
  id: string;
  fn: (draft: WorkflowState) => void;
  patches: Patch[];
}

function buildNode() {
  return { id: crypto.randomUUID() };
}

function buildEdge() {
  return { id: crypto.randomUUID() };
}

export const createWorkflowStore = (
  initProps?: Partial<WorkflowProps>,
  onChange?: (pendingAction: PendingAction) => void
) => {
  const DEFAULT_PROPS: WorkflowProps = {
    triggers: [],
    jobs: [],
    edges: [],
    workflow: null,
    change_id: null,
  };

  function proposeChanges(
    state: WorkflowState,
    fn: (draft: WorkflowState) => void
  ) {
    let patches: Patch[] = [];

    const nextState = produce(
      state,
      draft => {
        fn(draft);
      },
      (p: ImmerPatch[], _inverse: ImmerPatch[]) => {
        console.log(p);

        patches = p.map(patch => ({
          ...patch,
          path: `/${patch.path.join('/')}`,
        }));
      }
    );

    if (onChange) onChange({ id: crypto.randomUUID(), fn, patches });

    return nextState;
  }

  return createStore<WorkflowState>()(set => ({
    ...DEFAULT_PROPS,
    ...initProps,
    addJob: job => {
      set(state =>
        proposeChanges(state, draft => {
          const newJob = buildNode();
          draft.jobs.push(newJob);
        })
      );
    },
    addTrigger: trigger => {
      set(state =>
        proposeChanges(state, draft => {
          const newTrigger = buildNode();
          draft.triggers.push(newTrigger);
        })
      );
    },
    addEdge: edge => {
      set(state =>
        proposeChanges(state, draft => {
          const newEdge = buildEdge();
          draft.edges.push(newEdge);
        })
      );
    },
    setWorkflow: payload => {
      console.log('payload', payload);

      set(state =>
        produce(state, draft => {
          draft.jobs = payload.jobs;
          draft.triggers = payload.triggers;
          draft.edges = payload.edges;
          draft.workflow = payload;
        })
      );
    },
    applyPatches: patches => {
      const immerPatches: ImmerPatch[] = patches.map(patch => ({
        ...patch,
        path: patch.path.split('/').filter(Boolean),
      }));

      set(state => applyPatches(state, immerPatches));
    },
    onChange: onChange ? onChange : () => {},
  }));
};
