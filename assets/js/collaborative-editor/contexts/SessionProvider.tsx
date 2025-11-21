/**
 * SessionProvider - Handles shared Yjs document, awareness, and Phoenix Channel concerns
 * Provides common infrastructure for TodoStore and WorkflowStore
 *
 * Refactored to use focused hooks for better separation of concerns:
 * - useProviderLifecycle: Manages provider creation/reconnection
 * - ConnectionStatusProvider: Exposes connection state to components
 */

import type React from 'react';
import {
  createContext,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';

import _logger from '#/utils/logger';

import { useSocket } from '../../react/contexts/SocketProvider';
import { useURLState } from '../../react/lib/use-url-state';
import {
  createSessionStore,
  type SessionStoreInstance,
} from '../stores/createSessionStore';
import { ConnectionStatusProvider } from './ConnectionStatusContext';
import { useProviderLifecycle } from '../hooks/useProviderLifecycle';

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

  // Track initialization and sync state for ConnectionStatusContext
  const hasInitialized = useRef(false);
  const [isSynced, setIsSynced] = useState(false);
  const [lastSyncTime, setLastSyncTime] = useState<Date | null>(null);
  const [connectionError, setConnectionError] = useState<Error | null>(null);

  // Room naming strategy for snapshots vs collaborative editing:
  // - NO version param → `workflow:collaborate:${workflowId}` (latest/collaborative)
  // - WITH version param → `workflow:collaborate:${workflowId}:v${version}` (snapshot)
  const roomname = useMemo(
    () =>
      version
        ? `workflow:collaborate:${workflowId}:v${version}`
        : `workflow:collaborate:${workflowId}`,
    [version, workflowId]
  );

  const joinParams = useMemo(
    () => ({
      project_id: projectId,
      action: isNewWorkflow ? 'new' : 'edit',
    }),
    [projectId, isNewWorkflow]
  );

  // Initialize session once when connected
  useEffect(() => {
    if (!socket || !isConnected) {
      return;
    }

    // Prevent re-initialization if already done
    if (hasInitialized.current) {
      return;
    }

    logger.log('=== SessionProvider INITIALIZATION ===', {
      version,
      workflowId,
      isConnected,
    });

    logger.log('Initializing session (one-time)', {
      roomname,
      socketConnected: socket.isConnected(),
    });

    try {
      sessionStore.initializeSession(socket, roomname, null, {
        connect: true,
        joinParams,
      });

      logger.log('Session initialized with Y.Doc', {
        hasYDoc: !!sessionStore.ydoc,
      });

      hasInitialized.current = true;
      setConnectionError(null);
    } catch (error) {
      logger.error('Failed to initialize session', error);
      setConnectionError(error as Error);
    }
  }, [
    socket,
    workflowId,
    projectId,
    isNewWorkflow,
    sessionStore,
    version,
    isConnected,
    roomname,
    joinParams,
  ]);

  // Cleanup on unmount only - preserve Y.Doc during disconnections
  useEffect(() => {
    return () => {
      logger.debug('SessionProvider unmounting - destroying session', {
        version,
      });
      sessionStore.destroy();
      hasInitialized.current = false;
    };
  }, [sessionStore, version]);

  // Use provider lifecycle hook for reconnection management
  const handleProviderReady = useCallback(() => {
    logger.log('Provider ready');
    setIsSynced(false); // Will become true after sync
  }, []);

  const handleProviderReconnected = useCallback(() => {
    logger.log('Provider reconnected, syncing...');
    setIsSynced(false); // Will become true after sync
  }, []);

  useProviderLifecycle({
    socket,
    isConnected,
    sessionStore,
    roomname,
    joinParams,
    hasInitialized: hasInitialized.current,
    onProviderReady: handleProviderReady,
    onProviderReconnected: handleProviderReconnected,
  });

  // Track sync status from provider
  useEffect(() => {
    if (!sessionStore.provider) {
      setIsSynced(false);
      return;
    }

    const provider = sessionStore.provider;

    const handleSynced = (synced: boolean) => {
      setIsSynced(synced);
      if (synced) {
        setLastSyncTime(new Date());
      }
    };

    // Initial sync state
    handleSynced(provider.synced || false);

    // Listen for sync events
    provider.on('synced', handleSynced);

    return () => {
      provider.off('synced', handleSynced);
    };
  }, [sessionStore.provider]);

  // Testing and debug helpers
  useEffect(() => {
    // Testing helper to simulate a reconnect
    window.triggerSessionReconnect = (timeout = 1000) => {
      if (!socket) {
        console.error('Socket not available');
        return;
      }
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
  }, [sessionStore, socket]);

  // Memoize context value to prevent unnecessary re-renders
  // isNewWorkflow can change from true to false after user saves
  const contextValue = useMemo(
    () => ({ sessionStore, isNewWorkflow }),
    [sessionStore, isNewWorkflow]
  );

  return (
    <ConnectionStatusProvider
      isConnected={isConnected}
      isSynced={isSynced}
      lastSyncTime={lastSyncTime}
      error={connectionError}
    >
      <SessionContext.Provider value={contextValue}>
        {children}
      </SessionContext.Provider>
    </ConnectionStatusProvider>
  );
};
