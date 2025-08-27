/**
 * SessionStore
 *
 * Boilerplate store following the useSyncExternalStore + Immer pattern used
 * across the collaborative editor. Manages session-level connection state
 * and shared Yjs/Phoenix provider references.
 */

import { produce } from "immer";
import { Socket as PhoenixSocket } from "phoenix";
import { PhoenixChannelProvider } from "y-phoenix-channel";
import type * as awarenessProtocol from "y-protocols/awareness";
import { Awareness } from "y-protocols/awareness";
import { Doc as YDoc } from "yjs";

import logger from "#/utils/logger";

import type { LocalUserData } from "../types/awareness";

import { createWithSelector, type WithSelector } from "./common";

function debug(...args: Parameters<typeof logger.debug>) {
  logger.label("SessionStore").debug(...args);
}

export interface SessionState {
  ydoc: YDoc | null;
  provider: PhoenixChannelProvider | null;
  awareness: awarenessProtocol.Awareness | null;
  userData: LocalUserData | null;
  isConnected: boolean;
  isSynced: boolean;
  settled: boolean;
  lastStatus: string | null;
}

export interface SessionStore {
  subscribe: (listener: () => void) => () => void;
  getSnapshot: () => SessionState;
  withSelector: WithSelector<SessionState>;
  initializeYDoc: () => YDoc;
  destroyYDoc: () => void;
  initializeSession: (
    socket: PhoenixSocket | null,
    roomname: string,
    userData: LocalUserData | null,
    options?: { connect?: boolean }
  ) => {
    ydoc: YDoc;
    provider: PhoenixChannelProvider;
    awareness: awarenessProtocol.Awareness | null;
  };
  destroy: () => void;
  isReady: () => boolean;
  getProvider: () => PhoenixChannelProvider | null;
  getYDoc: () => YDoc | null;
  getConnectionState: () => boolean;
  getSyncState: () => boolean;
  getSettled: () => boolean;
  get isConnected(): boolean;
  get isSynced(): boolean;
  get settled(): boolean;
  get provider(): PhoenixChannelProvider | null;
  get ydoc(): YDoc | null;
  get awareness(): awarenessProtocol.Awareness | null;
}

type UpdateFn<T> = (updater: (draft: T) => void) => void;

export const createSessionStore = (): SessionStore => {
  let state: SessionState = produce(
    {
      ydoc: null,
      provider: null,
      awareness: null,
      userData: null,
      isConnected: false,
      isSynced: false,
      settled: false,
      lastStatus: null,
    } as SessionState,
    draft => draft
  );

  const listeners = new Set<() => void>();
  let cleanupProviderHandlers: (() => void) | null = null;
  let settlingSubscriptionCleanup: (() => void) | null = null;

  const notify = () => {
    listeners.forEach(listener => listener());
  };

  // Helper to update state
  const updateState: UpdateFn<SessionState> = updater => {
    const nextState = produce(state, updater);
    // const changedKeys = Object.keys(nextState).filter(key => {
    //   return nextState[key as keyof SessionState] !== state[key as keyof SessionState];
    // });
    // console.log("changedKeys", changedKeys);
    // if (changedKeys.length === 0) {
    //   console.log(new Error().stack);
    // }
    if (nextState !== state) {
      state = nextState;
      notify();
    }
    return nextState;
  };

  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  const getSnapshot = (): SessionState => state;
  const withSelector = createWithSelector(getSnapshot);

  // Commands (CQS)
  const initializeYDoc = () => {
    const ydoc = new YDoc();
    updateState(draft => {
      draft.ydoc = ydoc;
    });
    return ydoc;
  };

  const destroyYDoc = () => {
    if (state.ydoc) {
      state.ydoc.destroy();
    }

    // Clean up awareness if it exists
    if (state.awareness) {
      state.awareness.destroy();
    }

    updateState(draft => {
      draft.ydoc = null;
      draft.awareness = null;
      draft.userData = null;
    });
  };

  const initializeSession = (
    socket: PhoenixSocket | null,
    roomname: string,
    userData: LocalUserData | null = null,
    options: {
      connect?: boolean;
    } = {}
  ) => {
    // Atomic initialization to prevent partial states
    if (!socket) {
      throw new Error("Socket must be connected before initializing session");
    }

    // Step 1: Use existing YDoc or create new one
    const ydoc = state.ydoc || new YDoc();

    // Step 2: Create clean awareness instance if userData is provided
    let awarenessToUse = state.awareness;
    if (userData) {
      awarenessToUse = new Awareness(ydoc);
    }

    // Step 3: Create provider with YDoc and awareness
    const provider = new PhoenixChannelProvider(socket, roomname, ydoc, {
      awareness: awarenessToUse || undefined,
      connect: options.connect ?? true,
    });

    // Step 4: Update state atomically
    updateState(draft => {
      draft.ydoc = ydoc;
      draft.awareness = awarenessToUse;
      draft.provider = provider;
      draft.userData = userData;
      draft.isSynced = provider.synced;
    });

    // Step 5: Attach provider event handlers and store cleanup function
    cleanupProviderHandlers?.(); // Clean up any existing handlers
    cleanupProviderHandlers = attachProvider(provider, updateState);

    // Step 6: Initialize settling subscription if not already active
    settlingSubscriptionCleanup?.();
    settlingSubscriptionCleanup = createSettlingSubscription(
      subscribe,
      getSnapshot,
      updateState
    );

    return { ydoc, provider, awareness: awarenessToUse };
  };

  /**
   * destroy
   * - Calls settlingController.abort() which rejects the hanging promises
   * - Calls provider.destroy() which cleans up the PhoenixChannelProvider
   * - Calls ydoc.destroy() which cleans up the YDoc
   * - Resets all state to null
   */
  const destroy = () => {
    // Clean up all event handlers first
    cleanupProviderHandlers?.();
    cleanupProviderHandlers = null;

    // Clean up settling subscription
    settlingSubscriptionCleanup?.();
    settlingSubscriptionCleanup = null;

    state.provider?.destroy();
    state.awareness?.destroy();
    state.ydoc?.destroy();

    // Reset all state to initial values
    updateState(draft => {
      draft.provider = null;
      draft.ydoc = null;
      draft.awareness = null;
      draft.userData = null;
      draft.isConnected = false;
      draft.isSynced = false;
      draft.settled = false;
      draft.lastStatus = null;
    });
  };

  // Queries (CQS)
  const isReady = (): boolean => state.ydoc !== null && state.provider !== null;
  const getProvider = (): PhoenixChannelProvider | null => state.provider;
  const getYDoc = (): YDoc | null => state.ydoc;
  const getConnectionState = (): boolean => state.isConnected;
  const getSyncState = (): boolean => state.isSynced;
  const getSettled = (): boolean => state.settled;

  return {
    // Core store interface
    subscribe,
    getSnapshot,
    withSelector,

    // Commands
    initializeYDoc,
    destroyYDoc,
    initializeSession,
    destroy,

    // Queries
    isReady,
    getProvider,
    getYDoc,
    getConnectionState,
    getSyncState,
    getSettled,

    // Raw state accessors for convenience
    get isConnected() {
      return state.isConnected;
    },
    get isSynced() {
      return state.isSynced;
    },
    get settled() {
      return state.settled;
    },
    get provider() {
      return state.provider;
    },
    get ydoc() {
      return state.ydoc;
    },
    get awareness() {
      return state.awareness;
    },
  };
};

export type SessionStoreInstance = ReturnType<typeof createSessionStore>;

function attachProvider(
  provider: PhoenixChannelProvider,
  updateState: UpdateFn<SessionState>
) {
  const statusHandler = (event: { status: string }) => {
    const next = event.status;

    if (next) {
      const nowConnected = next === "connected";

      updateState(draft => {
        draft.isConnected = nowConnected;
        draft.lastStatus = next;
      });
    }
  };

  const syncHandler = (synced: boolean) => {
    updateState(draft => {
      draft.isSynced = synced;
    });
  };

  provider.on("status", statusHandler);
  provider.on("sync", syncHandler);

  return () => {
    provider.off("status", statusHandler);
    provider.off("sync", syncHandler);
  };
}

function createSettlingSubscription(
  subscribe: SessionStore["subscribe"],
  getSnapshot: SessionStore["getSnapshot"],
  updateState: UpdateFn<SessionState>
) {
  const state = getSnapshot();
  if (!state.provider || !state.ydoc) {
    throw new Error(
      "Provider and YDoc must be initialized before creating settling subscription"
    );
  }

  let currentController: AbortController | null = null;
  let currentlyConnected = state.isConnected;

  // Type-cast state since we've already verified provider and ydoc exist
  const stateWithProviderAndYdoc = state as SessionState & {
    provider: NonNullable<SessionState["provider"]>;
    ydoc: NonNullable<SessionState["ydoc"]>;
  };

  const startSettling = () => {
    // Abort any previous settling operation
    currentController?.abort();
    currentController = new AbortController();

    // Reset settled state
    updateState(draft => {
      draft.settled = false;
    });

    // Start waiting for settled state
    Promise.all([
      waitForChannelSynced(currentController, stateWithProviderAndYdoc),
      waitForFirstUpdate(currentController, stateWithProviderAndYdoc),
    ])
      .then(() => {
        if (!currentController?.signal.aborted) {
          updateState(draft => {
            debug("Settled");
            draft.settled = true;
          });
        }
        return undefined;
      })
      .catch(_e => {
        // Silently handle aborted/error cases
        // Settled state remains false
        return undefined;
      });
  };

  const onStateChange = () => {
    const newState = getSnapshot();

    // Detect transition from disconnected to connected
    if (newState.isConnected && !currentlyConnected) {
      currentlyConnected = true;
      // Restart settling process on reconnection
      startSettling();
    } else if (!newState.isConnected && currentlyConnected) {
      // Handle disconnection
      currentlyConnected = false;
      currentController?.abort();
      updateState(draft => {
        draft.settled = false;
      });
    }
  };

  const unsubscribe = subscribe(onStateChange);

  // Start initial settling if already connected, otherwise wait for connection
  if (currentlyConnected) {
    startSettling();
  }

  // Return cleanup function
  return () => {
    unsubscribe();
    currentController?.abort();
  };
}

function waitForChannelSynced(
  controller: AbortController,
  state: SessionState & {
    provider: NonNullable<SessionState["provider"]>;
  }
) {
  const { provider } = state;
  return new Promise<void>(resolve => {
    // if (provider.synced) {
    //   resolve();
    //   return;
    // }

    const cleanup = () => {
      provider.off("sync", handler);
    };

    const handler = (synced: boolean) => {
      if (synced) {
        cleanup();
        resolve();
      }
    };

    provider.on("sync", handler);

    controller.signal.addEventListener("abort", () => {
      cleanup();
      resolve();
    });
  });
}

function waitForFirstUpdate(
  controller: AbortController,
  state: SessionState & {
    ydoc: NonNullable<SessionState["ydoc"]>;
    provider: NonNullable<SessionState["provider"]>;
  }
) {
  const { ydoc, provider } = state;

  return new Promise<void>(resolve => {
    const cleanup = () => {
      ydoc.off("update", handler);
    };

    const handler = (_update: Uint8Array, origin: unknown) => {
      if (origin === provider) {
        cleanup();
        resolve();
      }
    };

    controller.signal.addEventListener("abort", () => {
      cleanup();
      resolve();
    });

    ydoc.on("update", handler);
  });
}
