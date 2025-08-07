/**
 * SessionProvider - Handles shared Yjs document, awareness, and Phoenix Channel concerns
 * Provides common infrastructure for TodoStore and WorkflowStore
 */

import React, { createContext, useContext, useEffect, useState } from 'react';
import * as Y from 'yjs';
import * as awarenessProtocol from 'y-protocols/awareness';
import { useSocket } from '../../react/contexts/SocketProvider';
import { PhoenixChannelProvider } from 'y-phoenix-channel';
import type { AwarenessUser } from '../types/session';

export interface SessionContextValue {
  // Yjs infrastructure
  ydoc: Y.Doc | null;
  awareness: awarenessProtocol.Awareness | null;

  // Connection state
  isConnected: boolean;
  isSynced: boolean;

  // User awareness
  users: AwarenessUser[];
}

const SessionContext = createContext<SessionContextValue | null>(null);

export const useSession = () => {
  const context = useContext(SessionContext);
  if (!context) {
    throw new Error('useSession must be used within a SessionProvider');
  }
  return context;
};

interface SessionProviderProps {
  workflowId: string;
  userId: string;
  userName: string;
  children: React.ReactNode;
}

export const SessionProvider: React.FC<SessionProviderProps> = ({
  workflowId,
  userId,
  userName,
  children,
}) => {
  const { socket, isConnected } = useSocket();

  // Yjs state
  const [ydoc, setYdoc] = useState<Y.Doc | null>(null);
  const [awareness, setAwareness] =
    useState<awarenessProtocol.Awareness | null>(null);
  const [_provider, setProvider] = useState<PhoenixChannelProvider | null>(
    null
  );

  // React state
  const [users, setUsers] = useState<AwarenessUser[]>([]);
  const [isProviderConnected, setIsProviderConnected] = useState(false);
  const [isSynced, setIsSynced] = useState(false);

  // Initialize Yjs when socket is connected
  useEffect(() => {
    if (!isConnected || !socket) {
      return;
    }

    console.log('🚀 Initializing Session with PhoenixChannelProvider');

    // Create Yjs document and awareness
    const doc = new Y.Doc();
    const awarenessInstance = new awarenessProtocol.Awareness(doc);

    // Set up awareness with user info
    const userData = {
      id: userId,
      name: userName,
      color: generateUserColor(userId),
    };

    awarenessInstance.setLocalStateField('user', userData);
    awarenessInstance.setLocalStateField('lastSeen', Date.now());

    // Create the Yjs channel provider
    const roomname = `workflow:collaborate:${workflowId}`;
    console.log('🔗 Creating PhoenixChannelProvider with:', {
      roomname,
      socketConnected: socket.isConnected(),
    });

    const channelProvider = new PhoenixChannelProvider(socket, roomname, doc, {
      awareness: awarenessInstance,
      connect: true,
    });

    console.debug('PhoenixChannelProvider: created', channelProvider);

    // IDEA: We could have two different states here, one for just the user
    // information, that is uniqued (in case they have more than one session)
    // and one for the cursor information.

    // TODO: Add an idle hook that both controls the updating of 'lastSeen'
    // and can mark a user as idle.

    // IDEA: perhaps take a note from LiveBlocks and their 'useSelf' hook
    // and have a 'useAwareness' hook that can be used to get the awareness
    // state for the current user.

    // Sync users from awareness
    // TODO: Perhaps move this this a hook, with a store or something immuatable?
    // The data changes very very frequently and we want to avoid re-rendering
    const syncUsers = () => {
      const userList: AwarenessUser[] = [];
      awarenessInstance.getStates().forEach((state, clientId) => {
        if (state['user']) {
          userList.push({
            clientId,
            user: state['user'],
            selection: state['selection'],
            cursor: state['cursor'],
          });
        }
      });
      setUsers(userList);
    };

    // Set up awareness observer
    awarenessInstance.on('change', syncUsers);

    // Provider event handlers
    const statusHandler = (...args: any[]) => {
      console.debug('PhoenixChannelProvider: status event', args);
      if (args.length > 0 && Array.isArray(args[0])) {
        const statusEvents = args[0];
        if (
          statusEvents[0] &&
          typeof statusEvents[0] === 'object' &&
          'status' in statusEvents[0]
        ) {
          const status = (statusEvents[0] as { status: string }).status;
          console.debug(
            'PhoenixChannelProvider: setIsProviderConnected',
            status
          );
          setIsProviderConnected(status === 'connected');
        }
      }
    };

    const syncHandler = (synced: boolean) => {
      console.debug('PhoenixChannelProvider: synced event', synced);
      setIsSynced(synced);
    };

    // Listen to provider status
    channelProvider.on('status', statusHandler);
    channelProvider.on('sync', syncHandler);

    // Also log initial provider state
    console.debug('PhoenixChannelProvider: initial state', {
      roomname,
      shouldConnect: channelProvider.shouldConnect,
      channel: channelProvider.channel,
      synced: channelProvider.synced,
      socketConnected: socket.isConnected(),
    });

    // Listen directly to channel for 'joined' state detection
    const cleanupJoinListener = setupJoinListener(
      channelProvider,
      isConnected => {
        setIsProviderConnected(isConnected);
      }
    );

    // Store state
    setYdoc(doc);
    setAwareness(awarenessInstance);
    setProvider(channelProvider);

    // Set up lastSeen timer - updates every 10 seconds
    const cleanupLastSeenTimer = setupLastSeenTimer(awarenessInstance);

    // Initial sync
    syncUsers();

    // Cleanup function
    return () => {
      console.debug('PhoenixChannelProvider: cleaning up');

      cleanupJoinListener();
      cleanupLastSeenTimer();

      channelProvider.off('status', statusHandler);
      channelProvider.off('sync', syncHandler);

      channelProvider.destroy();
      doc.destroy();
      setYdoc(null);
      setAwareness(null);
      setProvider(null);
      setUsers([]);
      setIsProviderConnected(false);
      setIsSynced(false);
    };
  }, [isConnected, socket, workflowId, userId, userName]);

  const value: SessionContextValue = {
    ydoc,
    awareness,
    isConnected: isProviderConnected,
    isSynced,
    users,
  };

  return (
    <SessionContext.Provider value={value}>{children}</SessionContext.Provider>
  );
};

// Helper functions
function generateUserColor(userId: string): string {
  const colors = [
    '#FF6B6B',
    '#4ECDC4',
    '#45B7D1',
    '#FFA07A',
    '#98D8C8',
    '#FFCF56',
    '#FF8B94',
    '#AED581',
  ];

  const hash = userId.split('').reduce((a, b) => {
    a = (a << 5) - a + b.charCodeAt(0);
    return a & a;
  }, 0);

  return colors[Math.abs(hash) % colors.length] || '#999999';
}

function setupJoinListener(
  channelProvider: PhoenixChannelProvider,
  callback: (isConnected: boolean) => void
) {
  const ref = channelProvider.channel?.on('phx_reply', (payload, ref) => {
    if (
      payload.status === 'ok' &&
      channelProvider.channel?.state === 'joined'
    ) {
      callback(true);
    }
  });

  return () => {
    channelProvider.channel?.off('phx_reply', ref);
  };
}

function setupLastSeenTimer(awarenessInstance: awarenessProtocol.Awareness) {
  const lastSeenTimer = setInterval(() => {
    awarenessInstance.setLocalStateField('lastSeen', Date.now());
  }, 10000);

  return () => {
    clearInterval(lastSeenTimer);
  };
}
