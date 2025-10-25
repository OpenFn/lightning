/**
 * SessionStore
 *
 * Boilerplate store following the useSyncExternalStore + Immer pattern used
 * across the collaborative editor. Manages session-level connection state
 * and shared Yjs/Phoenix provider references.
 */

/**
 * ## Session State Machine
 *
 * 1. Initial (ydoc: null, provider: null, isConnected: false, isSynced: false)
 *    ↓ initializeSession()
 * 2. Connecting (ydoc: YDoc, provider: Provider, isConnected: false, isSynced: false)
 *    ↓ Phoenix channel connects
 * 3. Connected (ydoc: YDoc, provider: Provider, isConnected: true, isSynced: false)
 *    ↓ Y.Doc receives initial sync
 * 4. Synced (ydoc: YDoc, provider: Provider, isConnected: true, isSynced: true)
 *    ↓ Ready for WorkflowStore connection
 *
 * On disconnect: Returns to step 2, then re-syncs to step 4
 */

/**
 * ## Redux DevTools Integration
 *
 * This store integrates with Redux DevTools for debugging in
 * development and test environments.
 *
 * **Features:**
 * - Real-time state inspection
 * - Action history with timestamps
 * - Time-travel debugging (jump to previous states)
 * - State export/import for reproducing bugs
 *
 * **Usage:**
 * 1. Install Redux DevTools browser extension
 * 2. Open DevTools and select the "SessionStore" instance
 * 3. Perform actions in the app and watch them appear in DevTools
 *
 * **Note:** DevTools is automatically disabled in production builds.
 *
 * **Excluded from DevTools:**
 * Y.Doc, Provider, Awareness (too large/circular)
 */

import { produce } from "immer";
import { Socket as PhoenixSocket } from "phoenix";
import { PhoenixChannelProvider } from "y-phoenix-channel";
import type * as awarenessProtocol from "y-protocols/awareness";
import { Awareness } from "y-protocols/awareness";
import { Doc as YDoc } from "yjs";

import _logger from "#/utils/logger";

import type { LocalUserData } from "../types/awareness";

import { createWithSelector, type WithSelector } from "./common";
import { wrapStoreWithDevTools } from "./devtools";

const logger = _logger.ns("SessionStore").seal();

export interface SessionState {
  ydoc: YDoc | null;
  provider: PhoenixChannelProvider | null;
  awareness: awarenessProtocol.Awareness | null;
  userData: LocalUserData | null;
  isConnected: boolean;
  isSynced: boolean;
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
  get isConnected(): boolean;
  get isSynced(): boolean;
  get provider(): PhoenixChannelProvider | null;
  get ydoc(): YDoc | null;
  get awareness(): awarenessProtocol.Awareness | null;
}

type UpdateFn<T> = (updater: (draft: T) => void, actionName?: string) => void;

export const createSessionStore = (): SessionStore => {
  let state: SessionState = produce(
    {
      ydoc: null,
      provider: null,
      awareness: null,
      userData: null,
      isConnected: false,
      isSynced: false,
      lastStatus: null,
    } as SessionState,
    draft => draft
  );

  const listeners = new Set<() => void>();
  let cleanupProviderHandlers: (() => void) | null = null;

  // Redux DevTools integration
  const devtools = wrapStoreWithDevTools({
    name: "SessionStore",
    excludeKeys: ["ydoc", "provider", "awareness"], // Exclude large Y.js objects
    maxAge: 100,
  });

  const notify = () => {
    listeners.forEach(listener => listener());
  };

  // Helper to update state
  const updateState: UpdateFn<SessionState> = (
    updater,
    actionName = "updateState"
  ) => {
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
      devtools.notifyWithAction(actionName, () => state);
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
    }, "initializeYDoc");
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
    }, "destroyYDoc");
  };

  const initializeSession = (
    socket: PhoenixSocket | null,
    roomname: string,
    userData: LocalUserData | null = null,
    options: {
      connect?: boolean;
      joinParams?: Record<string, unknown>;
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
      params: options.joinParams || {},
    });

    // Step 4: Update state
    updateState(draft => {
      draft.ydoc = ydoc;
      // Always use provider.awareness since PhoenixChannelProvider creates one if not provided
      draft.awareness = provider.awareness;
      draft.provider = provider;
      draft.userData = userData;
      draft.isSynced = provider.synced;
    }, "initializeSession");

    // Step 5: Attach provider event handlers and store cleanup function
    cleanupProviderHandlers?.(); // Clean up any existing handlers
    cleanupProviderHandlers = attachProvider(provider, updateState);

    devtools.connect();

    return { ydoc, provider, awareness: awarenessToUse };
  };

  /**
   * destroy
   * - Calls provider.destroy() which cleans up the PhoenixChannelProvider
   * - Calls ydoc.destroy() which cleans up the YDoc
   * - Resets all state to null
   */
  const destroy = () => {
    logger.debug("Destroying session");
    // Clean up all event handlers first
    cleanupProviderHandlers?.();
    cleanupProviderHandlers = null;

    state.provider?.destroy();
    state.awareness?.destroy();
    state.ydoc?.destroy();

    devtools.disconnect();

    // Reset all state to initial values
    updateState(draft => {
      draft.provider = null;
      draft.ydoc = null;
      draft.awareness = null;
      draft.userData = null;
      draft.isConnected = false;
      draft.isSynced = false;
      draft.lastStatus = null;
    }, "destroy");
  };

  // Queries (CQS)
  const isReady = (): boolean => state.ydoc !== null && state.provider !== null;
  const getProvider = (): PhoenixChannelProvider | null => state.provider;
  const getYDoc = (): YDoc | null => state.ydoc;
  const getConnectionState = (): boolean => state.isConnected;
  const getSyncState = (): boolean => state.isSynced;

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

    // Raw state accessors for convenience
    get isConnected() {
      return state.isConnected;
    },
    get isSynced() {
      return state.isSynced;
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
      }, "connectionStatusChange");
    }
  };

  const syncHandler = (synced: boolean) => {
    updateState(draft => {
      draft.isSynced = synced;
    }, "syncStatusChange");
  };

  provider.on("status", statusHandler);
  provider.on("sync", syncHandler);

  return () => {
    provider.off("status", statusHandler);
    provider.off("sync", syncHandler);
  };
}
