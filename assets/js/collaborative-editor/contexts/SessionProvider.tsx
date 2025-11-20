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

  // Track if we've initialized to prevent re-initialization
  const hasInitialized = useRef(false);

  // Initialize session once when connected
  useEffect(() => {
    if (!isConnected || !socket) return;

    // Prevent re-initialization if already done
    if (hasInitialized.current) {
      return;
    }

    logger.log('Initializing Session with PhoenixChannelProvider', { version });

    logger.log('=== SessionProvider INITIALIZATION ===', {
      version,
      workflowId,
      isConnected,
    });

    // Room naming strategy for snapshots vs collaborative editing:
    // - NO version param → `workflow:collaborate:${workflowId}` (latest/collaborative)
    // - WITH version param → `workflow:collaborate:${workflowId}:v${version}` (snapshot)
    const roomname = version
      ? `workflow:collaborate:${workflowId}:v${version}`
      : `workflow:collaborate:${workflowId}`;

    const joinParams = {
      project_id: projectId,
      action: isNewWorkflow ? 'new' : 'edit',
    };

    logger.log('Initializing session (one-time)', {
      roomname,
      socketConnected: socket.isConnected(),
    });

    sessionStore.initializeSession(socket, roomname, null, {
      connect: true,
      joinParams,
    });

    logger.log('Session initialized with Y.Doc', {
      hasYDoc: !!sessionStore.ydoc,
    });

    hasInitialized.current = true;
  }, [
    socket,
    workflowId,
    projectId,
    isNewWorkflow,
    sessionStore,
    version,
    isConnected,
  ]);

  // Cleanup on unmount only - in separate effect to avoid cleanup on reconnection
  useEffect(() => {
    return () => {
      logger.debug('SessionProvider unmounting - destroying session', {
        version,
      });
      sessionStore.destroy();
      hasInitialized.current = false;
    };
  }, [sessionStore, version]);

  // Handle reconnections separately - preserve Y.Doc, recreate provider
  useEffect(() => {
    if (!socket || !sessionStore.ydoc) {
      return;
    }

    // Only handle reconnection logic, not initial connection
    if (isConnected && sessionStore.provider) {
      // Already connected and have provider, nothing to do
      return;
    }

    if (isConnected && !sessionStore.provider) {
      // Reconnected but lost provider - recreate it
      logger.log('=== RECONNECTION DETECTED ===', {
        hasYDoc: !!sessionStore.ydoc,
        hasProvider: !!sessionStore.provider,
      });

      const roomname = version
        ? `workflow:collaborate:${workflowId}:v${version}`
        : `workflow:collaborate:${workflowId}`;

      const joinParams = {
        project_id: projectId,
        action: isNewWorkflow ? 'new' : 'edit',
      };

      logger.log('Recreating provider for reconnection', {
        roomname,
        willReuseYDoc: true,
      });

      // Reinitialize to create new provider but reuse existing Y.Doc
      sessionStore.initializeSession(socket, roomname, null, {
        connect: true,
        joinParams,
      });

      logger.log('Provider recreated, Y.Doc preserved', {
        hasYDoc: !!sessionStore.ydoc,
        hasProvider: !!sessionStore.provider,
      });
    }
  }, [
    isConnected,
    socket,
    workflowId,
    projectId,
    isNewWorkflow,
    sessionStore,
    version,
  ]);

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

    // Track Y.Doc updates during testing
    let updateCounter = 0;
    const updateLog: any[] = [];

    // Debug helper to start tracking updates
    window.startTrackingUpdates = () => {
      const ydoc = sessionStore.ydoc;
      if (!ydoc) {
        console.log('No Y.Doc instance');
        return;
      }

      updateCounter = 0;
      updateLog.length = 0;

      const handler = (update: Uint8Array, origin: any) => {
        updateCounter++;
        const log = {
          count: updateCounter,
          timestamp: new Date().toISOString(),
          updateSize: update.length,
          origin: origin?.constructor?.name || String(origin),
          connected: sessionStore.isConnected,
          providerSynced: sessionStore.provider?.synced,
        };
        updateLog.push(log);
        console.log('📝 Y.Doc Update:', log);
      };

      ydoc.on('update', handler);
      console.log('✅ Started tracking Y.Doc updates');

      return () => {
        ydoc.off('update', handler);
        console.log('🛑 Stopped tracking updates');
      };
    };

    // Debug helper to inspect Y.Doc content
    window.inspectYDoc = () => {
      const ydoc = sessionStore.ydoc;
      if (!ydoc) {
        console.log('No Y.Doc instance');
        return null;
      }

      const jobs = ydoc.getArray('jobs').toArray();
      const triggers = ydoc.getArray('triggers').toArray();
      const edges = ydoc.getArray('edges').toArray();

      const result = {
        jobs: jobs.map(j => {
          const body = j.get('body');
          let bodyPreview = '(empty)';
          if (body) {
            if (typeof body === 'string') {
              bodyPreview = body.substring(0, 50) + '...';
            } else if (body.toString) {
              const bodyStr = body.toString();
              bodyPreview = bodyStr.substring(0, 50) + '...';
            }
          }
          return {
            id: j.get('id'),
            name: j.get('name'),
            body: bodyPreview,
          };
        }),
        triggers: triggers.map(t => ({
          id: t.get('id'),
          type: t.get('type'),
        })),
        edges: edges.map(e => ({
          id: e.get('id'),
          source_job_id: e.get('source_job_id'),
          target_job_id: e.get('target_job_id'),
        })),
        provider: {
          exists: !!sessionStore.provider,
          synced: sessionStore.provider?.synced,
          connected: sessionStore.isConnected,
        },
        updateStats: {
          totalUpdates: updateCounter,
          recentUpdates: updateLog.slice(-5),
        },
      };

      console.log('Y.Doc Content:', result);
      return result;
    };
  }, [sessionStore, socket]);

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
