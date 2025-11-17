import invariant from 'tiny-invariant';
import { devtools } from 'zustand/middleware';
import { createStore } from 'zustand/vanilla';

import type { ReactComponentHook, RootMessage } from '#/react/types';

type Root = {
  hook?: ReactComponentHook | undefined;
  listeners?: Set<(message: RootMessage) => void> | undefined;
};

const prune = (roots: Map<string, Root>) => {
  for (const [id, { hook, listeners }] of roots) {
    if (hook == null && (listeners == null || listeners.size === 0)) {
      roots.delete(id);
    }
  }
  return new Map(roots);
};

type State = {
  roots: Map<string, Root>;
};

type Actions = {
  setListener: (
    id: string,
    listener: (message: RootMessage) => void
  ) => () => void;
  setRoot: (id: string, hook: ReactComponentHook) => () => void;
  getRoot: (id: string) => Root | undefined;
};

type RootStore = State & Actions;

export const createRootStore = () =>
  createStore<RootStore>()(
    devtools((set, get) => ({
      roots: new Map(),

      setListener: (id, listener) => {
        set(({ roots }) => {
          const { hook, listeners } = roots.get(id) ?? {};
          return {
            roots: new Map(roots).set(id, {
              hook,
              listeners: new Set(listeners).add(listener),
            }),
          };
        });

        const unsetListener = () => {
          set(({ roots }) => {
            const { hook, listeners } = roots.get(id) ?? {};
            invariant(listeners && listeners.has(listener));
            listeners.delete(listener);
            return {
              roots: prune(
                roots.set(id, { hook, listeners: new Set(listeners) })
              ),
            };
          });
        };

        return unsetListener;
      },

      setRoot: (id, hook) => {
        set(({ roots }) => {
          const { hook: storedHook, listeners } = roots.get(id) ?? {};
          invariant(storedHook == null);
          return {
            roots: new Map(roots).set(id, {
              hook,
              listeners,
            }),
          };
        });

        const unsetRoot = () => {
          set(({ roots }) => {
            const { hook: storedHook, listeners } = roots.get(id) ?? {};
            invariant(storedHook != null && hook === storedHook);
            return {
              roots: prune(roots.set(id, { listeners })),
            };
          });
        };

        return unsetRoot;
      },

      getRoot: id => get().roots.get(id),
    }))
  );
