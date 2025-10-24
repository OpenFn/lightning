/**
 * # StoreProvider
 *
 * Manages store instances (adaptorStore, credentialStore, awarenessStore) and handles
 * their lifecycle based on session state. This component separates store management
 * from session management, providing proper separation of concerns.
 *
 * ## Key Responsibilities:
 * - Creates and manages store instances
 * - Initializes awareness when both awareness instance and userData are available
 * - Connects/disconnects stores based on session state
 * - Provides store instances via StoreContext
 *
 * ## Architecture:
 * ```
 * SessionProvider (session state)
 *   ↓ useSession
 * StoreProvider (store management)
 *   ↓ useStores
 * Components (consume stores)
 * ```
 */

import type React from "react";
import {
  createContext,
  useContext,
  useEffect,
  useState,
  useSyncExternalStore,
} from "react";

import _logger from "#/utils/logger";

import { SessionContext } from "../contexts/SessionProvider";
import { useSession } from "../hooks/useSession";
import type { AdaptorStoreInstance } from "../stores/createAdaptorStore";
import { createAdaptorStore } from "../stores/createAdaptorStore";
import {
  type AwarenessStoreInstance,
  createAwarenessStore,
} from "../stores/createAwarenessStore";
import {
  type CredentialStoreInstance,
  createCredentialStore,
} from "../stores/createCredentialStore";
import {
  createSessionContextStore,
  type SessionContextStoreInstance,
} from "../stores/createSessionContextStore";
import { createUIStore, type UIStoreInstance } from "../stores/createUIStore";
import {
  createWorkflowStore,
  type WorkflowStoreInstance,
} from "../stores/createWorkflowStore";
import type { Session } from "../types/session";
import { generateUserColor } from "../utils/userColor";

export interface StoreContextValue {
  adaptorStore: AdaptorStoreInstance;
  credentialStore: CredentialStoreInstance;
  awarenessStore: AwarenessStoreInstance;
  workflowStore: WorkflowStoreInstance;
  sessionContextStore: SessionContextStoreInstance;
  uiStore: UIStoreInstance;
}

export const StoreContext = createContext<StoreContextValue | null>(null);

interface StoreProviderProps {
  children: React.ReactNode;
}

const logger = _logger.ns("StoreProvider").seal();

export const StoreProvider = ({ children }: StoreProviderProps) => {
  const session = useSession();

  // Get isNewWorkflow from SessionContext
  const sessionContext = useContext(SessionContext);
  const isNewWorkflow = sessionContext?.isNewWorkflow ?? false;

  // Create store instances once and reuse them
  const [stores] = useState(() => ({
    adaptorStore: createAdaptorStore(),
    credentialStore: createCredentialStore(),
    awarenessStore: createAwarenessStore(),
    workflowStore: createWorkflowStore(),
    sessionContextStore: createSessionContextStore(isNewWorkflow),
    uiStore: createUIStore(),
  }));

  // Subscribe to sessionContextStore user changes
  // Note: We use useSyncExternalStore directly here (not useUser hook) because
  // this is StoreProvider itself - the hooks require StoreContext to be available,
  // which we're in the process of providing.
  const user = useSyncExternalStore(
    stores.sessionContextStore.subscribe,
    stores.sessionContextStore.withSelector(state => state.user)
  );

  // Initialize awareness when both awareness instance and user data are available
  // User data comes from SessionContextStore, not from props
  useEffect(() => {
    logger.debug("Awareness initialization check", {
      hasAwareness: !!session.awareness,
      hasUser: !!user,
      user: user,
      isReady: stores.awarenessStore.isAwarenessReady(),
    });

    if (
      session.awareness &&
      user &&
      user.id &&
      user.first_name &&
      user.last_name &&
      !stores.awarenessStore.isAwarenessReady()
    ) {
      // Create LocalUserData from SessionContextStore user
      const userData = {
        id: user.id,
        name: `${user.first_name} ${user.last_name}`,
        color: generateUserColor(user.id),
      };

      logger.debug("Initializing awareness", { userData });

      // AwarenessStore is the ONLY place that sets awareness local state
      stores.awarenessStore.initializeAwareness(session.awareness, userData);

      // Set up last seen timer
      const cleanupTimer = stores.awarenessStore._internal.setupLastSeenTimer();

      return cleanupTimer;
    }
    return undefined;
  }, [session.awareness, user, stores.awarenessStore]);

  // Connect stores when provider is ready
  useEffect(() => {
    if (session.provider && session.isConnected) {
      logger.debug("Connecting stores to channel");

      const cleanup1 = stores.adaptorStore._connectChannel(session.provider);
      const cleanup2 = stores.credentialStore._connectChannel(session.provider);
      const cleanup3 = stores.sessionContextStore._connectChannel(
        session.provider
      );

      return () => {
        logger.debug("Disconnecting stores from channel");
        cleanup1();
        cleanup2();
        cleanup3();
      };
    }
    return undefined;
  }, [session.provider, session.isConnected, stores]);

  // Connect/disconnect workflowStore Y.Doc when session changes
  useEffect(() => {
    if (session.ydoc && session.provider && session.isConnected) {
      logger.debug("Connecting workflowStore");
      stores.workflowStore.connect(
        session.ydoc as Session.WorkflowDoc,
        session.provider
      );

      return () => {
        logger.debug("Disconnecting workflowStore from Y.Doc");
        stores.workflowStore.disconnect();
      };
    } else {
      return undefined;
    }
  }, [
    session.ydoc,
    session.provider,
    stores.workflowStore,
    session.isConnected,
  ]);

  useEffect(() => {
    return () => {
      logger.debug("Cleaning up awareness on unmount");
      stores.awarenessStore.destroyAwareness();
    };
  }, [stores.awarenessStore]);

  return (
    <StoreContext.Provider value={stores}>{children}</StoreContext.Provider>
  );
};
