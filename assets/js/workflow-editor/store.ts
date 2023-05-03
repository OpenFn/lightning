import type { Patch as ImmerPatch } from 'immer';
import { applyPatches, enablePatches, produce } from 'immer';
import { createStore } from 'zustand';

enablePatches();

type WorkflowProps = {
  triggers: {}[];
  jobs: {}[];
  edges: {}[];
  editJobUrl: string;
};

export interface WorkflowState extends WorkflowProps {
  addEdge: (edge: any) => void;
  addJob: (job: any) => void;
  addTrigger: (node: any) => void;
  onChange: (pendingAction: PendingAction) => void;
  applyPatches: (patches: Patch[]) => void;
}

// Immer's Patch type has an array of strings for the path, but RFC 6902
// specifies that the path should be a string. This is a workaround.
export type Patch = {
  path: string;
} & Omit<ImmerPatch, 'path'>;

// TODO: we aren't using the `id` property anywhere currently, but it could be
// required when reconciling out of date changes.
export interface PendingAction {
  id: string;
  fn: (draft: WorkflowState) => void;
  patches: Patch[];
}

// Build a new node, with the bare minimum properties.
function buildNode() {
  return { id: crypto.randomUUID() };
}

// Build a new trigger, with the bare minimum properties.
function buildTrigger() {
  return { id: crypto.randomUUID() };
}

// Build a new edge, with the bare minimum properties.
function buildEdge() {
  return { id: crypto.randomUUID() };
}

function toRFC6902Patch(patch: ImmerPatch): Patch {
  return {
    ...patch,
    path: `/${patch.path.join('/')}`,
  };
}

export const createWorkflowStore = (
  initProps?: Partial<WorkflowProps>,
  onChange?: (pendingAction: PendingAction) => void
) => {
  const DEFAULT_PROPS: WorkflowProps = {
    triggers: [],
    jobs: [],
    edges: [],
    editJobUrl: '',
  };

  // Calculate the next state using Immer, and then call the onChange callback
  // with the patches resulting from the change.
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
        patches = p.map(toRFC6902Patch);
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
          const newTrigger = buildTrigger();
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
