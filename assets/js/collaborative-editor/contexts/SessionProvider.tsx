/**
 * SessionProvider - Handles shared Yjs document, awareness, and Phoenix Channel concerns
 * Provides common infrastructure for TodoStore and WorkflowStore
 */

import type React from 'react';
import { createContext, useEffect, useMemo, useRef, useState } from 'react';

import _logger from '#/utils/logger';

import { useSocket } from '../../react/contexts/SocketProvider';
import { useURLState } from '../../react/lib/use-url-state';
import {
  createSessionStore,
  type SessionStoreInstance,
} from '../stores/createSessionStore';

const logger = _logger.ns('SessionProvider').seal();

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

  // Get version from URL reactively
  const { searchParams } = useURLState();
  const version = searchParams.get('v');

  // Create store instance once - stable reference
  const [sessionStore] = useState(() => createSessionStore());

  // Track if this is the initial mount or a reconnection
  const isInitialMount = useRef(true);
  const prevConnectedRef = useRef(isConnected);

  useEffect(() => {
    if (!isConnected || !socket) return;

    logger.log('Initializing Session with PhoenixChannelProvider', { version });

    // Track previous connection state
    if (!isConnected) {
      prevConnectedRef.current = isConnected;
      return;
    }

    // Detect reconnection: was disconnected, now connected, not initial mount
    const isReconnection =
      !prevConnectedRef.current && isConnected && !isInitialMount.current;

    logger.log('Initializing Session with PhoenixChannelProvider', {
      version,
      isReconnection,
      isInitialMount: isInitialMount.current,
    });

    // Create the Yjs channel provider
    // IMPORTANT: Room naming strategy for snapshots vs collaborative editing:
    // - NO version param (?v not in URL) → `workflow:collaborate:${workflowId}`
    //   This is the "latest" room where all users collaborate in real-time
    //   Everyone in this room sees the same state and moves forward together
    // - WITH version param (?v=22) → `workflow:collaborate:${workflowId}:v22`
    //   This is a separate, isolated room for viewing that specific snapshot
    //   Users viewing old versions don't interfere with users on latest
    const roomname = version
      ? `workflow:collaborate:${workflowId}:v${version}`
      : `workflow:collaborate:${workflowId}`;

    logger.log('Creating PhoenixChannelProvider with:', {
      roomname,
      socketConnected: socket.isConnected(),
      version,
      isLatestRoom: !version,
      isReconnection,
    });

    // Initialize session - createSessionStore handles everything
    // Pass null for userData - StoreProvider will initialize it from SessionContextStore
    const joinParams = {
      project_id: projectId,
      action: isNewWorkflow ? 'new' : 'edit',
    };

    // Always initialize session, even on reconnection
    // PhoenixChannelProvider handles reconnection internally, but we need
    // to ensure SessionStore event handlers are attached to track connection state
    sessionStore.initializeSession(socket, roomname, null, {
      connect: true,
      joinParams,
    });

    // Mark that we've completed initial mount
    isInitialMount.current = false;
    prevConnectedRef.current = isConnected;

    // Testing helper to simulate a reconnect
    window.triggerSessionReconnect = (timeout = 1000) => {
      socket.disconnect(
        () => {
          logger.log('socket disconnected');
          setTimeout(() => {
            socket.connect();
            logger.log('socket connected');
          }, timeout);
        },
        undefined,
        'Testing reconnect'
      );
    };

    // Cleanup function - only destroy on unmount, not on reconnection
    return () => {
      logger.debug('PhoenixChannelProvider: cleaning up', { version });

      // Only destroy if we're unmounting (not just disconnecting)
      // Unmount is detected by checking if socket is still valid
      if (socket) {
        sessionStore.destroy();
      }
    };
  }, [
    isConnected,
    socket,
    workflowId,
    projectId,
    isNewWorkflow,
    sessionStore,
    version,
  ]);

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
