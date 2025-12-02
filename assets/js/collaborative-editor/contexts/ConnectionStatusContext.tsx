/**
 * ConnectionStatusContext - Centralized connection state management
 *
 * Provides connection status information to all components in the tree.
 * Makes it easy to show connection indicators, offline status, and sync state.
 */

import type React from 'react';
import { createContext, useContext, useMemo } from 'react';

export interface ConnectionStatus {
  /** Whether the socket is currently connected */
  isConnected: boolean;

  /** Whether the Y.Doc provider is synced with the server */
  isSynced: boolean;

  /** Timestamp of last successful sync */
  lastSyncTime: Date | null;

  /** Current error if any */
  error: Error | null;

  /** Whether the session is transitioning to a new version */
  isTransitioning: boolean;
}

const ConnectionStatusContext = createContext<ConnectionStatus | null>(null);

export interface ConnectionStatusProviderProps {
  children: React.ReactNode;
  isConnected: boolean;
  isSynced: boolean;
  lastSyncTime: Date | null;
  error: Error | null;
  isTransitioning: boolean;
}

/**
 * Provider component that wraps the app and provides connection status
 */
export function ConnectionStatusProvider({
  children,
  isConnected,
  isSynced,
  lastSyncTime,
  error,
  isTransitioning,
}: ConnectionStatusProviderProps) {
  const value = useMemo(
    () => ({
      isConnected,
      isSynced,
      lastSyncTime,
      error,
      isTransitioning,
    }),
    [isConnected, isSynced, lastSyncTime, error, isTransitioning]
  );

  return (
    <ConnectionStatusContext.Provider value={value}>
      {children}
    </ConnectionStatusContext.Provider>
  );
}

/**
 * Hook to access connection status from any component
 *
 * @example
 * const { isConnected, isSynced } = useConnectionStatus();
 *
 * if (!isConnected) {
 *   return <OfflineIndicator />;
 * }
 */
export function useConnectionStatus(): ConnectionStatus {
  const context = useContext(ConnectionStatusContext);

  if (!context) {
    throw new Error(
      'useConnectionStatus must be used within ConnectionStatusProvider'
    );
  }

  return context;
}
