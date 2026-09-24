/**
 * SocketProvider - Manages Phoenix Socket connection
 * Uses existing Lightning user token authentication
 */

import { Socket as PhoenixSocket } from 'phoenix';
import { PHX_LV_DEBUG } from 'phoenix_live_view/constants';
import React, { createContext, useContext, useEffect, useState } from 'react';

interface SocketContextValue {
  socket: PhoenixSocket | null;
  isConnected: boolean;
  connectionError: string | null;
}

// Exported for tests that need to supply a connected socket context directly
// (e.g. integration tests that render the real SessionProvider without
// standing up a real PhoenixSocket).
export const SocketContext = createContext<SocketContextValue | null>(null);

export const useSocket = () => {
  const context = useContext(SocketContext);
  if (!context) {
    throw new Error('useSocket must be used within a SocketProvider');
  }
  return context;
};

interface SocketProviderProps {
  children: React.ReactNode;
}

export const SocketProvider: React.FC<SocketProviderProps> = ({ children }) => {
  const [socket, setSocket] = useState<PhoenixSocket | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [connectionError, setConnectionError] = useState<string | null>(null);

  useEffect(() => {
    // Get user token from window (set by Lightning's root layout)
    const userToken = (window as any).userToken;
    if (!userToken) {
      setConnectionError('No user token available');
      return;
    }

    const newSocket = new PhoenixSocket('/socket', {
      params: { token: userToken },
      logger: (kind: any, msg: any, data: any) => {
        // Follow the LiveView debug mode
        if (sessionStorage.getItem(PHX_LV_DEBUG) === 'true') {
          console.log(`Phoenix Socket ${kind}:`, msg, data);
        }
      },
    });

    newSocket.onOpen(() => {
      console.log('✅ Socket connected');
      setIsConnected(true);
      setConnectionError(null);
    });

    newSocket.onError((error: any) => {
      console.error('❌ Socket connection error:', error);
      setIsConnected(false);
      setConnectionError(error?.toString() || 'Connection error');
    });

    newSocket.onClose(() => {
      console.log('🔌 Socket disconnected');
      setIsConnected(false);
    });

    newSocket.connect();
    setSocket(newSocket);

    return () => {
      newSocket.disconnect();
    };
  }, []);

  const value: SocketContextValue = {
    socket,
    isConnected,
    connectionError,
  };

  return (
    <SocketContext.Provider value={value}>{children}</SocketContext.Provider>
  );
};
