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
import { Doc as YDoc } from "yjs";

import { createWithSelector } from "./common";

export interface SessionState {
  ydoc: YDoc | null;
  provider: PhoenixChannelProvider | null;
  awareness: awarenessProtocol.Awareness | null;
  isConnected: boolean;
  isSynced: boolean;
  settled: boolean;
  lastStatus: string | null;
}

export const createSessionStore = () => {
  let state: SessionState = produce(
    {
      ydoc: null,
      provider: null,
      awareness: null,
      isConnected: false,
      isSynced: false,
      settled: false,
      lastStatus: null,
    } as SessionState,
    draft => draft
  );

  const listeners = new Set<() => void>();
  let cleanupProviderHandlers: (() => void) | null = null;
  let settlingController: AbortController | null = null;

  const notify = () => {
    listeners.forEach(listener => listener());
  };

  const startSettling = () => {
    // Reset settled state immediately
    state = produce(state, draft => {
      draft.settled = false;
    });
    notify();

    // Cleanup previous settling attempt if any
    if (settlingController) {
      settlingController.abort();
    }

    const { ydoc, provider } = state;
    if (!ydoc || !provider) {
      return;
    }

    settlingController = new AbortController();
    const controller = settlingController;

    const channelSyncedPromise = new Promise<void>((resolve, reject) => {
      const cleanup = () => {
        provider.off("sync", handler);
      };

      const handler = (synced: boolean) => {
        if (synced) {
          cleanup();
          resolve();
        }
      };

      controller.signal.addEventListener("abort", () => {
        cleanup();
        reject(new Error("Aborted"));
      });

      provider.on("sync", handler);
    });

    const firstUpdatePromise = new Promise<void>((resolve, reject) => {
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
        reject(new Error("Aborted"));
      });

      ydoc.on("update", handler);
    });

    Promise.all([channelSyncedPromise, firstUpdatePromise])
      .then(() => {
        if (!controller.signal.aborted) {
          state = produce(state, draft => {
            draft.settled = true;
          });
          notify();
        }
        return undefined;
      })
      .catch(() => {
        // Silently handle aborted/error cases
        // Settled state remains false
        return undefined;
      });
  };

  // Core store interface
  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  const getSnapshot = (): SessionState => state;
  const withSelector = createWithSelector(getSnapshot);

  // Provider wiring
  const attachProvider = (provider: PhoenixChannelProvider) => {
    const statusHandler = (events: Array<{ status: string }>) => {
      const next = events[0]?.status;

      if (next) {
        const wasConnected = state.isConnected;
        const nowConnected = next === "connected";

        state = produce(state, draft => {
          draft.isConnected = nowConnected;
          draft.lastStatus = next;
        });
        notify();

        // Start settling when connection is established (including reconnections)
        if (nowConnected && !wasConnected) {
          startSettling();
        }
      }
    };

    const syncHandler = (synced: boolean) => {
      state = produce(state, draft => {
        draft.isSynced = synced;
      });
      notify();
    };

    provider.on("status", statusHandler);
    provider.on("sync", syncHandler);

    // Start initial settling if provider is already connected
    if (state.isConnected) {
      startSettling();
    }

    return () => {
      // @ts-expect-error - EventMap is not typed correctly in the library
      provider.off("status", statusHandler);
      provider.off("sync", syncHandler);
    };
  };

  // Commands (CQS)
  const initializeYDoc = () => {
    const ydoc = new YDoc();
    state = produce(state, draft => {
      draft.ydoc = ydoc;
    });
    notify();
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

    state = produce(state, draft => {
      draft.ydoc = null;
      draft.awareness = null;
    });
    notify();
  };

  const setAwareness = (awareness: awarenessProtocol.Awareness | null) => {
    state = produce(state, draft => {
      draft.awareness = awareness;
    });
    notify();
  };

  const initializeSession = (
    socket: PhoenixSocket | null,
    roomname: string,
    awareness: awarenessProtocol.Awareness | null = null,
    options: {
      connect?: boolean;
    } = {}
  ) => {
    // Atomic initialization to prevent partial states
    if (!socket) {
      throw new Error("Socket must be connected before initializing session");
    }

    // Step 1: Initialize YDoc if not already present
    let ydoc = state.ydoc;
    if (!ydoc) {
      ydoc = new YDoc();
    }

    // Step 2: Set awareness if provided
    const awarenessToUse = awareness || state.awareness;

    // Step 3: Create provider with YDoc and awareness
    const provider = new PhoenixChannelProvider(socket, roomname, ydoc, {
      awareness: awarenessToUse || undefined,
      connect: options.connect ?? true,
    });

    // Step 4: Update state atomically
    state = produce(state, draft => {
      draft.ydoc = ydoc;
      draft.awareness = awarenessToUse;
      draft.provider = provider;
      draft.isSynced = provider.synced;
    });
    notify();

    return { ydoc, provider, awareness: awarenessToUse };
  };

  const createProvider = (
    socket: PhoenixSocket | null,
    roomname: string,
    options: {
      awareness?: awarenessProtocol.Awareness;
      connect?: boolean;
    } = {}
  ) => {
    if (!state.ydoc) {
      throw new Error("YDoc must be initialized before creating provider");
    }

    if (!socket) {
      throw new Error("Socket must be connected before creating provider");
    }

    // Use stored awareness if no awareness is provided in options
    const awarenessToUse = options.awareness || state.awareness;

    const provider = new PhoenixChannelProvider(socket, roomname, state.ydoc, {
      awareness: awarenessToUse || undefined,
      connect: options.connect ?? true,
    });

    state = produce(state, draft => {
      draft.provider = provider;
      draft.isSynced = provider.synced;
    });
    notify();

    return provider;
  };

  const connectProvider = (provider: PhoenixChannelProvider) => {
    // Clean up any existing wiring
    cleanupProviderHandlers?.();
    cleanupProviderHandlers = null;

    state = produce(state, draft => {
      draft.provider = provider;
      draft.isSynced = provider.synced;
    });
    notify();

    cleanupProviderHandlers = attachProvider(provider);
  };

  const disconnectProvider = () => {
    cleanupProviderHandlers?.();
    cleanupProviderHandlers = null;

    // Abort any ongoing settling
    if (settlingController) {
      settlingController.abort();
      settlingController = null;
    }

    // Clean up provider if it exists
    if (state.provider) {
      state.provider.destroy();
    }

    // Clean up awareness if it exists
    if (state.awareness) {
      state.awareness.destroy();
    }

    // Clean up YDoc if it exists
    if (state.ydoc) {
      state.ydoc.destroy();
    }

    state = produce(state, draft => {
      draft.provider = null;
      draft.ydoc = null;
      draft.awareness = null;
      draft.isConnected = false;
      draft.isSynced = false;
      draft.settled = false;
      draft.lastStatus = null;
    });
    notify();
  };

  const destroySession = () => {
    // Clean up all event handlers first
    cleanupProviderHandlers?.();
    cleanupProviderHandlers = null;

    // Abort any ongoing settling
    if (settlingController) {
      settlingController.abort();
      settlingController = null;
    }

    // Clean up provider if it exists (includes channel cleanup)
    if (state.provider) {
      state.provider.destroy();
    }

    // Clean up awareness if it exists
    if (state.awareness) {
      state.awareness.destroy();
    }

    // Clean up YDoc if it exists
    if (state.ydoc) {
      state.ydoc.destroy();
    }

    // Reset all state to initial values
    state = produce(state, draft => {
      draft.provider = null;
      draft.ydoc = null;
      draft.awareness = null;
      draft.isConnected = false;
      draft.isSynced = false;
      draft.settled = false;
      draft.lastStatus = null;
    });
    notify();
  };

  const setYDoc = (doc: YDoc | null) => {
    state = produce(state, draft => {
      draft.ydoc = doc;
    });
    notify();
  };

  // Queries (CQS)
  const isReady = (): boolean => state.ydoc !== null && state.provider !== null;
  const getProvider = (): PhoenixChannelProvider | null => state.provider;
  const getYDoc = (): YDoc | null => state.ydoc;
  const getAwareness = (): awarenessProtocol.Awareness | null =>
    state.awareness;
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
    setAwareness,
    initializeSession,
    createProvider,
    connectProvider,
    disconnectProvider,
    destroySession,
    setYDoc,

    // Queries
    isReady,
    getProvider,
    getYDoc,
    getAwareness,
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
