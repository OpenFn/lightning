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
import { createContext, useEffect, useState } from "react";

import logger from "#/utils/logger";

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
  createWorkflowStore,
  type WorkflowStoreInstance,
} from "../stores/createWorkflowStore";
import type { Session } from "../types/session";

export interface StoreContextValue {
  adaptorStore: AdaptorStoreInstance;
  credentialStore: CredentialStoreInstance;
  awarenessStore: AwarenessStoreInstance;
  workflowStore: WorkflowStoreInstance;
}

export const StoreContext = createContext<StoreContextValue | null>(null);

interface StoreProviderProps {
  children: React.ReactNode;
}

export const StoreProvider = ({ children }: StoreProviderProps) => {
  const session = useSession();

  // Create store instances once and reuse them
  const [stores] = useState(() => ({
    adaptorStore: createAdaptorStore(),
    credentialStore: createCredentialStore(),
    awarenessStore: createAwarenessStore(),
    workflowStore: createWorkflowStore(),
  }));

  // Initialize awareness when both awareness instance and userData are available
  useEffect(() => {
    if (
      session.awareness &&
      session.userData &&
      !stores.awarenessStore.isAwarenessReady()
    ) {
      console.debug("StoreProvider: Initializing awareness", {
        userData: session.userData,
      });

      // AwarenessStore is the ONLY place that sets awareness local state
      stores.awarenessStore.initializeAwareness(
        session.awareness,
        session.userData
      );

      // Set up last seen timer
      // TODO: the awarenessStore should be responsible for this
      // TODO: also the destroyAwareness call should be in this effect.
      const cleanupTimer = stores.awarenessStore._internal.setupLastSeenTimer();

      return cleanupTimer;
    }
    return undefined;
  }, [session.awareness, session.userData, stores]);

  // Connect stores when provider is ready
  useEffect(() => {
    if (session.provider && session.isConnected) {
      logger.label("StoreProvider").debug("Connecting stores to channel");

      const cleanup1 = stores.adaptorStore._connectChannel(session.provider);
      const cleanup2 = stores.credentialStore._connectChannel(session.provider);

      return () => {
        console.debug("StoreProvider: Disconnecting stores from channel");
        cleanup1();
        cleanup2();
      };
    }
    return undefined;
  }, [session.provider, session.isConnected, stores]);

  // Connect/disconnect workflowStore Y.Doc when session changes
  useEffect(() => {
    if (session.ydoc && session.provider && session.isConnected) {
      logger.label("StoreProvider").debug("Connecting workflowStore");
      stores.workflowStore.connect(
        session.ydoc as Session.WorkflowDoc,
        session.provider
      );

      return () => {
        logger
          .label("StoreProvider")
          .debug("Disconnecting workflowStore from Y.Doc");
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

  // Clean up awareness when session is destroyed
  useEffect(() => {
    return () => {
      console.debug("StoreProvider: Cleaning up awareness on unmount");
      stores.awarenessStore.destroyAwareness();
    };
  }, [stores.awarenessStore]);

  return (
    <StoreContext.Provider value={stores}>{children}</StoreContext.Provider>
  );
};
