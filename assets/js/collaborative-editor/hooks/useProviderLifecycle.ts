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

import type { Socket } from 'phoenix';
import { useEffect, useRef, useState } from 'react';

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

  /** Callback when provider initialization fails */
  onError?: (error: Error) => void;

  /** Callback when provider is ready (initial connection) */
  onProviderReady?: () => void;

  /** Callback when provider is reconnected */
  onProviderReconnected?: () => void;
}

export interface ProviderLifecycleResult {
  /** Whether provider has been initialized at least once */
  hasProviderInitialized: boolean;

  /** Last initialization error, if any */
  initError: Error | null;
}

/**
 * Hook that manages provider lifecycle with reconnection support
 *
 * Responsibilities:
 * - Creates provider on initial connection (once Y.Doc exists)
 * - Recreates provider on reconnection (preserving Y.Doc)
 * - Handles initialization errors
 * - Reports provider initialization state
 *
 * Note: Y.Doc lifecycle is managed separately by useYDocPersistence
 *
 * @example
 * const { hasProviderInitialized, initError } = useProviderLifecycle({
 *   socket,
 *   isConnected,
 *   sessionStore,
 *   roomname: 'workflow:collaborate:xyz',
 *   joinParams: { project_id: '123', action: 'edit' },
 *   onError: (error) => setConnectionError(error),
 *   onProviderReconnected: () => console.log('Syncing...'),
 * });
 */
export function useProviderLifecycle({
  socket,
  isConnected,
  sessionStore,
  roomname,
  joinParams,
  onError,
  onProviderReady,
  onProviderReconnected,
}: ProviderLifecycleOptions): ProviderLifecycleResult {
  const hasProviderInitialized = useRef(false);
  const [initError, setInitError] = useState<Error | null>(null);
  const prevProviderRef = useRef(sessionStore.provider);

  // Handle initial provider creation
  useEffect(() => {
    if (!socket || !isConnected) {
      return;
    }

    // Skip initialization if store is transitioning (migration in progress)
    if (sessionStore.isTransitioning()) {
      logger.log('Skipping provider initialization during migration');
      return;
    }

    // Initial connection: create provider if not initialized
    // Note: This will create Y.Doc as part of initialization
    if (!hasProviderInitialized.current && !sessionStore.provider) {
      logger.log('Creating initial provider', { roomname });

      try {
        sessionStore.initializeSession(socket, roomname, null, {
          connect: true,
          joinParams,
        });

        hasProviderInitialized.current = true;
        setInitError(null);
        onError?.(null as any); // Clear error
        onProviderReady?.();
      } catch (error) {
        const err = error as Error;
        logger.error('Failed to initialize provider', err);
        setInitError(err);
        onError?.(err);
      }
    }
  }, [
    socket,
    isConnected,
    sessionStore,
    roomname,
    joinParams,
    onError,
    onProviderReady,
  ]);

  // Separate effect to detect provider loss and handle reconnection
  useEffect(() => {
    const hadProvider = prevProviderRef.current !== null;
    const hasProvider = sessionStore.provider !== null;

    // Skip reconnection if store is transitioning (migration in progress)
    if (sessionStore.isTransitioning()) {
      logger.log('Skipping reconnection during migration');
      prevProviderRef.current = sessionStore.provider;
      return;
    }

    // Detect provider loss: had provider but now don't
    if (
      hadProvider &&
      !hasProvider &&
      hasProviderInitialized.current &&
      socket &&
      isConnected
    ) {
      logger.log('Provider lost - reconnecting', {
        roomname,
        willReuseYDoc: true,
      });

      try {
        // Reinitialize to create new provider but reuse existing Y.Doc
        sessionStore.initializeSession(socket, roomname, null, {
          connect: true,
          joinParams,
        });

        setInitError(null);
        onError?.(null as any); // Clear error
        onProviderReconnected?.();
      } catch (error) {
        const err = error as Error;
        logger.error('Failed to reconnect provider', err);
        setInitError(err);
        onError?.(err);
      }
    }

    // Update ref for next comparison
    prevProviderRef.current = sessionStore.provider;
  }, [
    sessionStore.provider,
    socket,
    isConnected,
    sessionStore,
    roomname,
    joinParams,
    onError,
    onProviderReconnected,
  ]);

  return {
    hasProviderInitialized: hasProviderInitialized.current,
    initError,
  };
}
