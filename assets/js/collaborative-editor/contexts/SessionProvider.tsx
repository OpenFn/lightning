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
import { useYDocPersistence } from '../hooks/useYDocPersistence';

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
  const { params } = useURLState();
  const version = params.v ?? null;

  // Create store instance once - stable reference
  const [sessionStore] = useState(() => createSessionStore());

  // Track sync state for ConnectionStatusContext
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

  // Handle roomname changes (version switching)
  // When roomname changes, destroy session in cleanup to allow reinitialization
  useEffect(() => {
    return () => {
      logger.log('Room changing - destroying session for reinitialization', {
        roomname,
      });
      sessionStore.destroy();
    };
  }, [roomname, sessionStore]);

  // Use Y.Doc persistence hook to manage Y.Doc lifecycle
  const handleYDocInitialized = useCallback(() => {
    logger.log('Y.Doc initialized', { version });
  }, [version]);

  const handleYDocDestroyed = useCallback(() => {
    logger.log('Y.Doc destroyed (version change or unmount)', { version });
    setIsSynced(false);
    setLastSyncTime(null);
    setConnectionError(null);
  }, [version]);

  useYDocPersistence({
    sessionStore,
    shouldInitialize: socket !== null && isConnected,
    version,
    onInitialized: handleYDocInitialized,
    onDestroyed: handleYDocDestroyed,
  });

  // Use provider lifecycle hook to manage provider initialization
  const handleProviderError = useCallback((error: Error | null) => {
    setConnectionError(error);
  }, []);

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
    onError: handleProviderError,
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

    const handleSync = (synced: boolean) => {
      setIsSynced(synced);
      if (synced) {
        setLastSyncTime(new Date());
      }
    };

    // Initial sync state
    handleSync(provider.synced || false);

    // Listen for sync events
    provider.on('sync', handleSync);

    return () => {
      provider.off('sync', handleSync);
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
