import type { Patch as ImmerPatch } from 'immer';

import { applyPatches, enablePatches, produce } from 'immer';
import { createStore } from 'zustand';
import type { Lightning } from '../workflow-diagram/types';

enablePatches();

export type RemoveArgs = {
  jobs?: string[];
  triggers?: string[];
  edges?: string[];
};

export type ChangeArgs = Partial<WorkflowProps>;

export type AddArgs = ChangeArgs;

export type WorkflowProps = {
  triggers: Lightning.TriggerNode[];
  jobs: Lightning.JobNode[];
  edges: Lightning.Edge[];
};

export interface WorkflowState extends WorkflowProps {
  add: (data: AddArgs) => void;
  change: (data: ChangeArgs) => void;
  remove: (data: RemoveArgs) => void;
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
    add: data => {
      set(state =>
        proposeChanges(state, draft => {
          ['jobs', 'triggers', 'edges'].forEach(k => {
            const key = k as keyof WorkflowProps;
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
    remove: data => {
      set(state =>
        proposeChanges(state, draft => {
          ['jobs', 'triggers', 'edges'].forEach(k => {
            const key = k as keyof WorkflowProps;

            const idsToRemove = data[key]!;
            if (idsToRemove) {
              const nextItems: any[] = [];
              draft[key].forEach(item => {
                if (!idsToRemove.includes(item.id)) {
                  nextItems.push(item);
                }
              });
              draft[key] = nextItems;
            }
          });
        })
      );
    },
    change: data => {
      set(state =>
        proposeChanges(state, draft => {
          for (const [t, changes] of Object.entries(data)) {
            const type = t as 'jobs' | 'triggers' | 'edges';
            for (const change of changes) {
              const current = draft[type] as Array<
                Lightning.Node | Lightning.Edge
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
    applyPatches: patches => {
      const immerPatches: ImmerPatch[] = patches.map(patch => ({
        ...patch,
        path: patch.path.split('/').filter(Boolean),
      }));

      set(state => applyPatches(state, immerPatches));
    },
    onChange,
  }));
};
