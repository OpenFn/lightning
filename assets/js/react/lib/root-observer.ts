import type { ReactComponentHook, RootMessage } from '#/react/types';

import { createRootStore } from './root-store';

export class RootObserver {
  readonly #store = createRootStore();

  get #roots() {
    return this.#store.getState();
  }

  #notify(id: string, message: RootMessage) {
    const listeners = this.#roots.getRoot(id)?.listeners;
    if (!listeners) return;

    for (const listener of listeners) {
      listener(message);
    }
  }

  mounted(id: string, hook: ReactComponentHook) {
    const unsetRoot = this.#roots.setRoot(id, hook);
    this.#notify(id, { type: 'mounted', hook });

    const beforeUnmount = () => {
      this.#notify(id, { type: 'beforeUnmount' });
      unsetRoot();
    };

    return beforeUnmount;
  }

  subscribe(id: string, listener: (event: RootMessage) => void) {
    const unsetListener = this.#roots.setListener(id, listener);

    const hook = this.#roots.getRoot(id)?.hook;

    if (hook != null) {
      listener({ type: 'mounted', hook });
    }

    const unsubscribe = () => {
      unsetListener();
    };

    return unsubscribe;
  }
}
