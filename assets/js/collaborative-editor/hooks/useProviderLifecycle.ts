/**
 * useProviderLifecycle - Manages PhoenixChannelProvider lifecycle
 *
 * This hook is responsible for:
 * - Creating provider when socket connects
 * - Recreating provider on reconnection (while preserving Y.Doc)
 * - Cleaning up provider resources
 *
 * Key principle: Provider can be recreated, but Y.Doc must persist.
 */

import { useEffect } from 'react';
import type { Socket } from 'phoenix';

import _logger from '#/utils/logger';

import type { SessionStoreInstance } from '../stores/createSessionStore';

const logger = _logger.ns('useProviderLifecycle').seal();

export interface ProviderLifecycleOptions {
  /** Phoenix socket instance */
  socket: Socket | null;

  /** Whether socket is connected */
  isConnected: boolean;

  /** Session store instance */
  sessionStore: SessionStoreInstance;

  /** Room name for the channel */
  roomname: string;

  /** Parameters for joining the channel */
  joinParams: Record<string, any>;

  /** Whether provider has been initialized at least once */
  hasInitialized: boolean;

  /** Callback when provider is ready */
  onProviderReady?: () => void;

  /** Callback when provider is reconnected */
  onProviderReconnected?: () => void;
}

/**
 * Hook that manages provider lifecycle with reconnection support
 *
 * @example
 * useProviderLifecycle({
 *   socket,
 *   isConnected,
 *   sessionStore,
 *   roomname: 'workflow:collaborate:xyz',
 *   joinParams: { project_id: '123', action: 'edit' },
 *   hasInitialized: true,
 *   onProviderReconnected: () => console.log('Syncing...'),
 * });
 */
export function useProviderLifecycle({
  socket,
  isConnected,
  sessionStore,
  roomname,
  joinParams,
  hasInitialized,
  onProviderReady,
  onProviderReconnected,
}: ProviderLifecycleOptions): void {
  // Handle initial provider creation and reconnections
  useEffect(() => {
    if (!socket || !sessionStore.ydoc) {
      return;
    }

    // Initial connection: create provider if not initialized
    if (isConnected && !hasInitialized && !sessionStore.provider) {
      logger.log('Creating initial provider', { roomname });

      sessionStore.initializeSession(socket, roomname, null, {
        connect: true,
        joinParams,
      });

      onProviderReady?.();
      return;
    }

    // Reconnection: recreate provider if we have Y.Doc but lost provider
    if (isConnected && hasInitialized && !sessionStore.provider) {
      logger.log('=== RECONNECTION DETECTED ===', {
        hasYDoc: !!sessionStore.ydoc,
        hasProvider: !!sessionStore.provider,
      });

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

      onProviderReconnected?.();
    }
  }, [
    socket,
    isConnected,
    sessionStore,
    roomname,
    joinParams,
    hasInitialized,
    onProviderReady,
    onProviderReconnected,
  ]);
}
