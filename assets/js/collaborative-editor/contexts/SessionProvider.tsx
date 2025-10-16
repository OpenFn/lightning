/**
 * SessionProvider - Handles shared Yjs document, awareness, and Phoenix Channel concerns
 * Provides common infrastructure for TodoStore and WorkflowStore
 */

import type React from "react";
import { createContext, useEffect, useMemo, useState } from "react";

import _logger from "#/utils/logger";

import { useSocket } from "../../react/contexts/SocketProvider";
import {
  createSessionStore,
  type SessionStoreInstance,
} from "../stores/createSessionStore";

const logger = _logger.ns("SessionProvider").seal();

interface SessionContextValue {
  sessionStore: SessionStoreInstance;
  isNewWorkflow: boolean;
}

export const SessionContext = createContext<SessionContextValue | null>(null);

interface SessionProviderProps {
  workflowId: string;
  projectId: string;
  isNewWorkflow: boolean;
  children: React.ReactNode;
}

export const SessionProvider = ({
  workflowId,
  projectId,
  isNewWorkflow,
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
    sessionStore.initializeSession(socket, roomname, null, {
      connect: true,
      joinParams: {
        project_id: projectId,
        action: isNewWorkflow ? "new" : "edit",
      },
    });

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
  }, [isConnected, socket, workflowId, projectId, isNewWorkflow, sessionStore]);

  // Memoize context value to prevent unnecessary re-renders
  // isNewWorkflow can change from true to false after user saves
  const contextValue = useMemo(
    () => ({ sessionStore, isNewWorkflow }),
    [sessionStore, isNewWorkflow]
  );

  return (
    <SessionContext.Provider value={contextValue}>
      {children}
    </SessionContext.Provider>
  );
};
