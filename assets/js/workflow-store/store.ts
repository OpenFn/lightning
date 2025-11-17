import type { XYPosition } from '@xyflow/react';
import type { Patch as ImmerPatch } from 'immer';
import {
  applyPatches as immerApplyPatches,
  enablePatches,
  produce,
} from 'immer';
import { createStore, useStore, type StoreApi } from 'zustand';

import { randomUUID } from '../common';
import type { Lightning, Positions } from '../workflow-diagram/types';

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
  selection: string | null;
  positions: Positions | null;
  runSteps: RunInfo;
  history: WorkflowRunHistory;
};

export type RunStep = {
  id: string;
  job_id: Lightning.Job['id'];
  error_type: string | null;
  exit_reason: 'fail' | 'success' | 'crash' | null;
  started_at: string;
  finished_at: string;
  input_dataclip_id: string;
  // below don't come from backend
  startNode?: boolean;
  startBy: string;
};

export type RunInfo = {
  start_from: string | null;
  inserted_at: string;
  isTrigger: boolean;
  steps: RunStep[];
  run_by: string | null;
};

export type WorkOrderStates = 'failed' | 'success' | 'crashed';
export type WorkflowRunHistory = Array<{
  id: string;
  state: WorkOrderStates;
  last_activity: string;
  version: number;
  runs: Array<{
    id: string;
    state: string;
    error_type: string;
    started_at: string;
    finished_at: string;
    selected?: boolean;
  }>;
  selected?: boolean;
}>;

export interface WorkflowState extends WorkflowProps {
  forceFit: boolean;
  setForceFit: (v: boolean) => void;
  setState: (
    partial:
      | WorkflowState
      | Partial<WorkflowState>
      | ((state: WorkflowState) => WorkflowState | Partial<WorkflowState>),
    replace?: boolean
  ) => void;
  observer: null | ((v: unknown) => void);
  reset: () => void;
  subscribe: (cb: (v: unknown) => void) => void;
  undo: () => void;
  redo: () => void;
  add: (data: AddArgs) => void;
  updatePositions: (data: Positions | null) => void;
  updatePosition: (nodeId: string, pos: XYPosition) => void;
  change: (data: ChangeArgs) => void;
  remove: (data: RemoveArgs) => void;
  rebase: (data: Partial<WorkflowProps>) => void;
  getById: <T = Lightning.Node | Lightning.Edge | Lightning.TriggerNode>(
    id?: string
  ) => T | undefined;
  getItem: (
    id?: string
  ) => Lightning.TriggerNode | Lightning.JobNode | Lightning.Edge | undefined;
  applyPatches: (patches: Partial<ReplayAction>) => void;
  setDisabled: (value: boolean) => void;
  setSelection: (value: string) => void;
  updateRuns: (
    runs: RunInfo,
    run_id: string | null,
    history?: WorkflowRunHistory
  ) => void;
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

export type ReplayAction = {
  patches: ImmerPatch[];
  inverse: ImmerPatch[];
};

let undos: ReplayAction[] = [];
let redos: ReplayAction[] = [];

export const RUNS_TMP: RunInfo = {
  steps: [],
  isTrigger: false,
  start_from: null,
  inserted_at: '',
  run_by: null,
};

// simple squash function
// I think after squashing. we can actually ignore in-between states.
function pushUndo(action: ReplayAction) {
  const lastAction = undos[undos.length - 1];
  if (lastAction) {
    const firstPatch = lastAction.patches[0];
    const patch = action.patches[0];
    if (
      firstPatch &&
      firstPatch.path.join('.') === patch?.path.join('.') &&
      patch.path.length >= 3
    ) {
      lastAction.patches = [...lastAction.patches, ...action.patches];
      lastAction.inverse = [...action.inverse, ...lastAction.inverse];
      redos = [];
      return;
    }
  }
  undos.push(action);
  redos = [];
}

// Calculate the next state using Immer, and then call the onChange callback
// with the patches resulting from the change.
function proposeChanges(
  state: WorkflowState,
  fn: (draft: WorkflowState) => void,
  onChange?: (v: unknown) => void,
  skipUndoStack = false // set to true for the actual undo/redo action to prevent an undo loop
) {
  let patches: Patch[] = [];

  const nextState = produce(
    state,
    draft => {
      fn(draft);
    },
    (p: ImmerPatch[], _inverse: ImmerPatch[]) => {
      if (!skipUndoStack && !state.disabled) {
        pushUndo({ patches: p, inverse: _inverse });
      }
      patches = p.map(toRFC6902Patch);
    }
  );

  console.debug('Proposing changes', patches);

  if (onChange) onChange({ id: randomUUID(), fn, patches });

  return nextState;
}

const DEFAULT_PROPS: WorkflowProps = {
  triggers: [],
  jobs: [],
  edges: [],
  disabled: false,
  selection: null,
  positions: null,
  runSteps: RUNS_TMP,
  history: [],
};

export type WorkflowStore = StoreApi<WorkflowState>;
// just trust this singleton - [works on the assumption that workflowEditor will instantiate(currently true) before jobEditor tries to use it]
export const store: WorkflowStore = createStore<WorkflowState>()(
  (set, get) => ({
    ...DEFAULT_PROPS,
    forceFit: false,
    setForceFit(v) {
      set({ forceFit: v });
    },
    observer: null,
    subscribe: cb => {
      if (get().observer) return;
      set({ observer: cb });
    },
    undo: () => {
      set(state => {
        return proposeChanges(
          state,
          draft => {
            const lastPatch = undos.pop();
            console.log('undoing:', lastPatch);
            if (!lastPatch) return draft;
            const newState = immerApplyPatches(draft, lastPatch.inverse);
            redos.push(lastPatch);
            return newState;
          },
          get().observer,
          true
        );
      });
    },
    redo: () => {
      set(state => {
        return proposeChanges(
          state,
          draft => {
            const lastPatch = redos.pop();
            if (!lastPatch) return draft;
            const newState = immerApplyPatches(draft, lastPatch.patches);
            undos.push(lastPatch);
            return newState;
          },
          get().observer,
          true
        );
      });
    },
    add: data => {
      console.log('add', data);

      set(state =>
        proposeChanges(
          state,
          draft => {
            (['jobs', 'triggers', 'edges', 'positions'] as const).forEach(
              <K extends 'jobs' | 'triggers' | 'edges' | 'positions'>(
                key: K
              ) => {
                const change = data[key];
                if (change && typeof change === 'object') {
                  if (Array.isArray(change)) {
                    // update an array
                    change.forEach(
                      (item: NonNullable<ChangeArgs[K]>[number]) => {
                        if (!item.id) {
                          item.id = randomUUID();
                        }
                        draft[key].push(item);
                      }
                    );
                  } else {
                    // update a plain object literal
                    Object.entries(change).forEach(([ckey, cvalue]) => {
                      if (draft[key]) draft[key][ckey] = cvalue;
                    });
                  }
                }
              }
            );
          },
          get().observer
        )
      );
    },
    remove: data => {
      set(state =>
        proposeChanges(
          state,
          draft => {
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
          },
          get().observer
        )
      );
    },
    updatePositions: data => {
      set(state =>
        proposeChanges(
          state,
          draft => {
            draft.positions = data;
          },
          get().observer
        )
      );
    },
    updatePosition(nodeId, pos) {
      set(state =>
        proposeChanges(
          state,
          draft => {
            if (draft.positions) {
              draft.positions = { ...draft.positions, [nodeId]: pos };
            }
          },
          get().observer
        )
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
        proposeChanges(
          state,
          draft => {
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
          },
          get().observer
        )
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
    getItem: id => {
      const { jobs, triggers, edges } = store.getState();
      const everything = [...jobs, ...triggers, ...edges];
      for (const i of everything) {
        if (id === i.id) {
          return i;
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
      proposeChanges(
        data,
        draft => {
          for (const [t, changes] of Object.entries(state)) {
            if (['triggers', 'jobs', 'edges'].includes(t)) {
              const type = t as 'jobs' | 'triggers' | 'edges';
              draft[type] = changes;
            }
          }
        },
        get().observer
      );
    },
    applyPatches: patches => {
      if (!patches.patches) return;
      const immerPatches: ImmerPatch[] = patches.patches.map(patch => ({
        ...patch,
        path: patch.path.split('/').filter(Boolean),
      }));

      // if there's an inverse, add this to undo stack
      if (patches.inverse && patches.inverse.length && !get().disabled) {
        // don't forget to prep inverse patches path.
        const inverseImmerPatches: ImmerPatch[] = patches.inverse.map(
          patch => ({
            ...patch,
            path: patch.path.split('/').filter(Boolean),
          })
        );
        pushUndo({ patches: immerPatches, inverse: inverseImmerPatches });
      }

      set(state => immerApplyPatches(state, immerPatches));
    },
    reset() {
      set(DEFAULT_PROPS);
    },
    setDisabled: (value: boolean) => {
      set(state => ({
        ...state,
        disabled: value,
      }));
    },
    setState(value) {
      undos = [];
      redos = [];
      get().updateRuns(RUNS_TMP, null);
      set(value);
    },
    setSelection(value) {
      set(state => ({
        ...state,
        selection: value,
      }));
    },
    updateRuns(runs, run_id, history) {
      set(state => {
        const _history = (history || state.history).map(wo => {
          let wselected = false;
          return {
            ...wo,
            runs: wo.runs.map(run => {
              const rselected = run.id === run_id;
              if (rselected) wselected = true;
              return { ...run, selected: rselected };
            }),
            selected: wselected,
          };
        });
        return {
          runSteps: runs,
          history: _history,
        };
      });
    },
  })
);

export const useWorkflowStore = () => {
  return useStore(store);
};
