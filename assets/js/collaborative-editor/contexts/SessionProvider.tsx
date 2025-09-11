/**
 * SessionProvider - Handles shared Yjs document, awareness, and Phoenix Channel concerns
 * Provides common infrastructure for TodoStore and WorkflowStore
 */

import type React from "react";
import { createContext, useEffect, useState } from "react";
import { PhoenixChannelProvider } from "y-phoenix-channel";

import _logger from "#/utils/logger";

import { useSocket } from "../../react/contexts/SocketProvider";
import type { AdaptorStoreInstance } from "../stores/createAdaptorStore";
import { createAdaptorStore } from "../stores/createAdaptorStore";
import {
  type AwarenessStoreInstance,
  createAwarenessStore,
} from "../stores/createAwarenessStore";
import {
  createCredentialStore,
  type CredentialStoreInstance,
} from "../stores/createCredentialStore";
import {
  createSessionStore,
  type SessionStoreInstance,
} from "../stores/createSessionStore";

const logger = _logger.ns("SessionProvider").seal();

export const SessionContext = createContext<SessionStoreInstance | null>(null);

interface SessionProviderProps {
  workflowId: string;
  userId: string;
  userName: string;
  children: React.ReactNode;
}

export const SessionProvider = ({
  workflowId,
  userId,
  userName,
  children,
}: SessionProviderProps) => {
  const { socket, isConnected } = useSocket();

  // Create store instance once - stable reference
  const [sessionStore] = useState(() => createSessionStore());

  // Store instances - created once and reused using lazy initialization
  // TODO: Remove these after StoreProvider is implemented
  const [adaptorStore] = useState<AdaptorStoreInstance>(() =>
    createAdaptorStore()
  );
  const [credentialStore] = useState<CredentialStoreInstance>(() =>
    createCredentialStore()
  );
  const [awarenessStore] = useState<AwarenessStoreInstance>(() =>
    createAwarenessStore()
  );

  useEffect(() => {
    if (!isConnected || !socket) return;

    logger.log("Initializing Session with PhoenixChannelProvider");

    // Set up user data for awareness
    const userData = {
      id: userId,
      name: userName,
      color: generateUserColor(userId),
    };

    // Create the Yjs channel provider
    const roomname = `workflow:collaborate:${workflowId}`;
    logger.log("Creating PhoenixChannelProvider with:", {
      roomname,
      socketConnected: socket.isConnected(),
    });

    // Initialize session - createSessionStore handles everything
    const { provider, awareness } = sessionStore.initializeSession(
      socket,
      roomname,
      userData,
      { connect: true }
    );

    // Initialize awareness store with the awareness instance
    if (awareness) {
      awarenessStore.initializeAwareness(awareness, userData);
    }

    // Testing helper to simulate a reconnect
    window.triggerSessionReconnect = (timeout = 1000) => {
      socket.disconnect(
        () => {
          logger.log("socket disconnected");
          setTimeout(() => {
            socket.connect();
            logger.log("socket connected");
          }, timeout);
        },
        undefined,
        "Testing reconnect"
      );
    };

    let cleanupAdaptorChannel: (() => void) | undefined;
    let cleanupCredentialChannel: (() => void) | undefined;

    // Listen directly to channel for 'joined' state detection
    const cleanupJoinListener = setupJoinListener(provider, isConnected => {
      // Request adaptors when channel is successfully joined
      logger.debug("joinListener", { isConnected });
    });

    // Set up automatic last seen updates via awareness store
    const cleanupLastSeenTimer = awarenessStore._internal.setupLastSeenTimer();

    // Cleanup function
    return () => {
      logger.debug("PhoenixChannelProvider: cleaning up");

      cleanupJoinListener();
      cleanupLastSeenTimer();
      cleanupAdaptorChannel?.();
      cleanupCredentialChannel?.();

      // Clean up awareness store
      awarenessStore.destroyAwareness();

      sessionStore.destroy();
    };
  }, [
    adaptorStore,
    awarenessStore,
    credentialStore,
    isConnected,
    socket,
    userId,
    userName,
    workflowId,
    sessionStore,
  ]);

  // Pass store instance directly - never changes reference
  return (
    <SessionContext.Provider value={sessionStore}>
      {children}
    </SessionContext.Provider>
  );
};

// Helper functions
function generateUserColor(userId: string): string {
  const colors = [
    "#FF6B6B",
    "#4ECDC4",
    "#45B7D1",
    "#FFA07A",
    "#98D8C8",
    "#FFCF56",
    "#FF8B94",
    "#AED581",
  ];

  const hash = userId.split("").reduce((a, b) => {
    a = (a << 5) - a + b.charCodeAt(0);
    return a & a;
  }, 0);

  return colors[Math.abs(hash) % colors.length] || "#999999";
}

function setupJoinListener(
  channelProvider: PhoenixChannelProvider,
  callback: (isConnected: boolean) => void
) {
  const onJoinReceived = () => {
    if (channelProvider.channel?.state === "joined") {
      callback(true);
    }
  };
  channelProvider.channel?.joinPush.receive("ok", onJoinReceived);

  return () => {
    const hooks = channelProvider.channel?.joinPush.recHooks as
      | Array<{ callback: () => void }>
      | undefined;
    const hook = hooks?.find(hook => hook.callback === onJoinReceived);
    if (hook && hooks) {
      hooks.splice(hooks.indexOf(hook), 1);
    }
  };
}
