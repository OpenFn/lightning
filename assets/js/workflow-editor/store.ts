import type { Patch as ImmerPatch } from 'immer';

import { applyPatches, enablePatches, produce } from 'immer';
import { createStore } from 'zustand';
import type { Lightning } from '../workflow-diagram/types';
import { randomUUID } from '../common';

enablePatches();

export type RemoveArgs = {
  jobs?: string[];
  triggers?: string[];
  edges?: string[];
};

export type AddArgs = ChangeArgs;

export type ChangeArgs = {
  triggers?: t.SetRequired<Partial<Lightning.TriggerNode>, 'id'>[];
  jobs?: t.SetRequired<Partial<Lightning.JobNode>, 'id'>[];
  edges?: t.SetRequired<Partial<Lightning.Edge>, 'id'>[];
};

export type WorkflowProps = {
  triggers: Lightning.TriggerNode[];
  jobs: Lightning.JobNode[];
  edges: Lightning.Edge[];
  disabled: boolean;
};

export interface WorkflowState extends WorkflowProps {
  add: (data: AddArgs) => void;
  change: (data: ChangeArgs) => void;
  remove: (data: RemoveArgs) => void;
  rebase: (data: Partial<WorkflowProps>) => void;
  getById: <T = Lightning.Node | Lightning.Edge | Lightning.TriggerNode>(
    id?: string | undefined
  ) => T | undefined;
  onChange: (pendingAction: PendingAction) => void;
  applyPatches: (patches: Patch[]) => void;
  setDisabled: (value: boolean) => void;
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

function toRFC6902Patch(patch: ImmerPatch): Patch {
  const newPatch = {
    path: `/${patch.path.join('/')}`,
    op: patch.value === undefined ? 'remove' : patch.op,
    value: patch.value,
  };

  if (newPatch.op === 'remove') {
    delete newPatch.value;
  }

  return newPatch;
}

export const createWorkflowStore = (
  initProps?: Partial<WorkflowProps>,
  onChange: (pendingAction: PendingAction) => void = () => {}
) => {
  const DEFAULT_PROPS: WorkflowProps = {
    triggers: [],
    jobs: [],
    edges: [],
    disabled: false,
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

    console.debug('Proposing changes', patches);

    if (onChange) onChange({ id: randomUUID(), fn, patches });

    return nextState;
  }

  return createStore<WorkflowState>()((set, get) => ({
    ...DEFAULT_PROPS,
    ...initProps,
    add: data => {
      console.log('add', data);

      set(state =>
        proposeChanges(state, draft => {
          (['jobs', 'triggers', 'edges'] as const).forEach(
            <K extends 'jobs' | 'triggers' | 'edges'>(key: K) => {
              const change = data[key];
              if (change) {
                change.forEach((item: NonNullable<ChangeArgs[K]>[number]) => {
                  if (!item.id) {
                    item.id = randomUUID();
                  }
                  draft[key].push(item);
                });
              }
            }
          );
        })
      );
    },
    remove: data => {
      set(state =>
        proposeChanges(state, draft => {
          (['jobs', 'triggers', 'edges'] as const).forEach(
            <K extends 'jobs' | 'triggers' | 'edges'>(key: K) => {
              const idsToRemove = data[key];
              if (idsToRemove) {
                const currentItems = draft[key];
                const nextItems: WorkflowState[K] = [];
                currentItems.forEach((item: WorkflowState[K][number]) => {
                  if (!idsToRemove.includes(item.id)) {
                    nextItems.push(item);
                  }
                });
                draft[key] = nextItems;
              }
            }
          );
        })
      );
    },
    // Change the state of the workflow. The data object should have the
    // following shape:
    //
    // ```
    // {
    //   jobs: [{ id: '123', body: 'new body' }],
    //   triggers: [{ id: '456', enabled: false }]
    // }
    // ```
    //
    // The `id` property is required for each item in the array.
    // You can provide as many or as few changes as you like.
    change: data => {
      set(state =>
        proposeChanges(state, draft => {
          for (const [t, changes] of Object.entries(data)) {
            const type = t as 'jobs' | 'triggers' | 'edges';
            for (const change of changes) {
              const current = draft[type] as Array<
                Lightning.TriggerNode | Lightning.JobNode | Lightning.Edge
              >;

              const item = current.find(i => i.id === change.id);
              if (item) {
                Object.assign(item, change);
              }
            }
          }
        })
      );
    },
    getById(id) {
      if (id == null) return;

      const state = get();

      for (const items of Object.entries(state).reduce((acc, [k, v]) => {
        if (['triggers', 'jobs', 'edges'].includes(k)) {
          acc.push(v);
        }
        return acc;
      }, [])) {
        const item = items.find(i => i.id === id);
        if (item) {
          return item;
        }
      }
    },
    // Experimental
    // Used to compare the current state with the state in the browser and
    // calculate the patches to apply to bring the server state in sync with the
    // client state.
    // Currently it just considers each item in the state as a whole and
    // replaces it with the new state. This is a naive approach and will need to
    // be improved to just the differences.
    rebase: data => {
      const state = get();
      proposeChanges(data, draft => {
        for (const [t, changes] of Object.entries(state)) {
          if (['triggers', 'jobs', 'edges'].includes(t)) {
            const type = t as 'jobs' | 'triggers' | 'edges';
            draft[type] = changes;
          }
        }
      });
    },
    applyPatches: patches => {
      const immerPatches: ImmerPatch[] = patches.map(patch => ({
        ...patch,
        path: patch.path.split('/').filter(Boolean),
      }));

      set(state => applyPatches(state, immerPatches));
    },
    onChange,
    setDisabled: (value: boolean) => {
      set(state => ({
        ...state,
        disabled: value,
      }));
    },
  }));
};

export type WorkflowStore = ReturnType<typeof createWorkflowStore>;
