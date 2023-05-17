import type { Patch as ImmerPatch } from 'immer';
import { applyPatches, enablePatches, produce } from 'immer';
import { createStore } from 'zustand';
import type { Lightning } from '../workflow-diagram/types';

enablePatches();

export type WorkflowProps = {
  triggers: Lightning.TriggerNode[];
  jobs: Lightning.JobNode[];
  edges: Lightning.Edge[];
  editJobUrl: string;
};

export interface WorkflowState extends WorkflowProps {
  add: (data: Partial<WorkflowProps>) => void;
  change: (data: Partial<WorkflowProps>) => void;
  remove: (data: {
    jobs?: string[];
    triggers?: string[];
    edges?: string[];
  }) => void;
  addEdge: (edge: Lightning.Edge) => void;
  addJob: (job: Lightning.JobNode) => void;
  addTrigger: (node: Lightning.TriggerNode) => void;
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

// Build a new job, with the bare minimum properties.
function buildJob(job = {}) {
  return { id: crypto.randomUUID(), ...job } as Lightning.JobNode;
}

// Build a new trigger, with the bare minimum properties.
function buildTrigger(trigger = {}) {
  return { id: crypto.randomUUID(), ...trigger } as Lightning.TriggerNode;
}

// Build a new edge, with the bare minimum properties.
function buildEdge(edge = {}) {
  return { id: crypto.randomUUID(), ...edge } as Lightning.Edge;
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
    // Bulk update API
    // (We rarely, if ever, only add one thing)
    // Uh that's not true, I think the store doesn't update until we apply?
    // So a change event will be published, but the store won't reflect the patch
    add: data => {
      set(state =>
        proposeChanges(state, draft => {
          ['jobs', 'triggers', 'edges'].forEach(k => {
            const key = k as keyof Omit<WorkflowProps, 'editJobUrl'>;
            if (data[key]) {
              data[key]!.forEach(item => {
                if (!item.id) {
                  item.id = crypto.randomUUID();
                }
                draft[key].push(item as any);
              });
            }
          });
        })
      );
    },
    // remove one or more things by id
    remove: data => {
      set(state =>
        proposeChanges(state, draft => {
          ['jobs', 'triggers', 'edges'].forEach(k => {
            const key = k as keyof Omit<WorkflowProps, 'editJobUrl'>;
            if (data[key]) {
              const newCollection: any[] = [];
              draft[key].forEach(item => {
                if (!data[key]!.includes(item.id)) {
                  newCollection.push(item);
                }
              });
              draft[key] = newCollection;
            }
          });
        })
      );
    },
    change: data => {
      set(state =>
        proposeChanges(state, draft => {
          for (const type in data) {
            for (const change of data[type]) {
              const item = draft[type].find(i => i.id === change.id);
              Object.assign(item, change);
            }
          }
        })
      );
    },
    addJob: job => {
      const newJob = buildJob(job);
      set(state =>
        proposeChanges(state, draft => {
          draft.jobs.push(newJob);
        })
      );
      return newJob;
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
      const newEdge = buildEdge(edge);
      set(state =>
        proposeChanges(state, draft => {
          draft.edges.push(newEdge);
        })
      );
      return newEdge;
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
