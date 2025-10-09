/**
 * SessionProvider - Handles shared Yjs document, awareness, and Phoenix Channel concerns
 * Provides common infrastructure for TodoStore and WorkflowStore
 */

import type React from "react";
import { createContext, useEffect, useState } from "react";

import _logger from "#/utils/logger";

import { useSocket } from "../../react/contexts/SocketProvider";
import {
  createSessionStore,
  type SessionStoreInstance,
} from "../stores/createSessionStore";

const logger = _logger.ns("SessionProvider").seal();

export const SessionContext = createContext<SessionStoreInstance | null>(null);

interface SessionProviderProps {
  workflowId: string;
  children: React.ReactNode;
}

export const SessionProvider = ({
  workflowId,
  children,
}: SessionProviderProps) => {
  const { socket, isConnected } = useSocket();

  // Create store instance once - stable reference
  const [sessionStore] = useState(() => createSessionStore());

  useEffect(() => {
    if (!isConnected || !socket) return;

    logger.log("Initializing Session with PhoenixChannelProvider");

    // Create the Yjs channel provider
    const roomname = `workflow:collaborate:${workflowId}`;
    logger.log("Creating PhoenixChannelProvider with:", {
      roomname,
      socketConnected: socket.isConnected(),
    });

    // Initialize session - createSessionStore handles everything
    // Pass null for userData - StoreProvider will initialize it from SessionContextStore
    sessionStore.initializeSession(socket, roomname, null, { connect: true });

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

    // Cleanup function
    return () => {
      logger.debug("PhoenixChannelProvider: cleaning up");
      sessionStore.destroy();
    };
  }, [isConnected, socket, workflowId, sessionStore]);

  // Pass store instance directly - never changes reference
  return (
    <SessionContext.Provider value={sessionStore}>
      {children}
    </SessionContext.Provider>
  );
};
