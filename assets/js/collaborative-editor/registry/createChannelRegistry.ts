/**
 * Channel Registry
 *
 * Manages concurrent channel connections during version transitions to prevent
 * flickering. When switching versions, the registry keeps both old and new
 * channels alive during the transition, only destroying the old channel after
 * the new one is fully settled.
 */

import type { Socket } from 'phoenix';
import { PhoenixChannelProvider } from 'y-phoenix-channel';
import { Awareness } from 'y-protocols/awareness';
import { Doc as YDoc } from 'yjs';

import _logger from '#/utils/logger';

import type {
  ChannelEntry,
  ChannelRegistry,
  ChannelState,
} from '../types/channelRegistry';

const logger = _logger.ns('ChannelRegistry').seal();

/**
 * Configuration constants for channel lifecycle management
 */
const REGISTRY_CONFIG = {
  // Grace period before destroying draining channel (2 seconds)
  drainGracePeriodMs: 2000,
  // Timeout for settling state (10 seconds)
  settlingTimeoutMs: 10000,
} as const;

/**
 * Creates a Channel Registry instance for managing concurrent channel
 * connections
 *
 * @returns ChannelRegistry instance
 */
export const createChannelRegistry = (): ChannelRegistry => {
  let currentEntry: ChannelEntry | null = null;
  let drainingEntry: ChannelEntry | null = null;
  const listeners = new Set<() => void>();
  let drainTimer: ReturnType<typeof setTimeout> | null = null;
  let settlingController: AbortController | null = null;

  const notify = () => {
    listeners.forEach(listener => listener());
  };

  /**
   * Subscribe to registry state changes
   */
  const subscribe = (callback: () => void): (() => void) => {
    listeners.add(callback);
    return () => listeners.delete(callback);
  };

  /**
   * Update entry state and notify subscribers
   */
  const updateEntryState = (
    entry: ChannelEntry,
    newState: ChannelState
  ): void => {
    logger.debug(`State transition: ${entry.state} → ${newState}`, {
      roomname: entry.roomname,
    });

    entry.state = newState;

    if (newState === 'active') {
      entry.settledAt = Date.now();
    }

    notify();
  };

  /**
   * Destroy a channel entry and clean up all resources
   */
  const destroyEntry = (entry: ChannelEntry): void => {
    logger.debug('Destroying entry', { roomname: entry.roomname });

    updateEntryState(entry, 'destroyed');

    try {
      entry.provider.destroy();
      entry.awareness.destroy();
      entry.ydoc.destroy();
    } catch (error) {
      logger.warn('Error destroying entry resources', {
        error,
        roomname: entry.roomname,
      });
    }
  };

  /**
   * Start drain timer for old entry after new entry becomes active
   */
  const startDrainTimer = (entry: ChannelEntry): void => {
    if (drainTimer) {
      clearTimeout(drainTimer);
    }

    logger.debug('Starting drain timer', {
      roomname: entry.roomname,
      gracePeriodMs: REGISTRY_CONFIG.drainGracePeriodMs,
    });

    drainTimer = setTimeout(() => {
      logger.debug('Drain timer elapsed, destroying entry', {
        roomname: entry.roomname,
      });

      destroyEntry(entry);

      if (drainingEntry === entry) {
        drainingEntry = null;
        notify();
      }

      drainTimer = null;
    }, REGISTRY_CONFIG.drainGracePeriodMs);
  };

  /**
   * Wait for provider to sync
   */
  const waitForProviderSync = (
    provider: PhoenixChannelProvider,
    controller: AbortController
  ): Promise<void> => {
    return new Promise<void>(resolve => {
      const cleanup = () => {
        provider.off('sync', handler);
      };

      const handler = (synced: boolean) => {
        if (synced) {
          cleanup();
          resolve();
        }
      };

      provider.on('sync', handler);

      controller.signal.addEventListener('abort', () => {
        cleanup();
        resolve();
      });
    });
  };

  /**
   * Wait for first Y.Doc update from provider
   */
  const waitForFirstUpdate = (
    ydoc: YDoc,
    provider: PhoenixChannelProvider,
    controller: AbortController
  ): Promise<void> => {
    return new Promise<void>(resolve => {
      const cleanup = () => {
        ydoc.off('update', handler);
      };

      const handler = (_update: Uint8Array, origin: unknown) => {
        if (origin === provider) {
          cleanup();
          resolve();
        }
      };

      controller.signal.addEventListener('abort', () => {
        cleanup();
        resolve();
      });

      ydoc.on('update', handler);
    });
  };

  /**
   * Wait for entry to settle (sync + first update)
   */
  const waitForSettled = async (
    entry: ChannelEntry,
    controller: AbortController
  ): Promise<void> => {
    logger.debug('Waiting for entry to settle', {
      roomname: entry.roomname,
    });

    try {
      // Create timeout promise
      const timeoutPromise = new Promise<void>((_, reject) => {
        const timeout = setTimeout(() => {
          reject(
            new Error(
              `Settling timeout after ${REGISTRY_CONFIG.settlingTimeoutMs}ms`
            )
          );
        }, REGISTRY_CONFIG.settlingTimeoutMs);

        controller.signal.addEventListener('abort', () => {
          clearTimeout(timeout);
        });
      });

      // Wait for both sync and first update, or timeout
      await Promise.race([
        Promise.all([
          waitForProviderSync(entry.provider, controller),
          waitForFirstUpdate(entry.ydoc, entry.provider, controller),
        ]),
        timeoutPromise,
      ]);

      if (!controller.signal.aborted) {
        logger.debug('Entry settled successfully', {
          roomname: entry.roomname,
        });

        updateEntryState(entry, 'active');

        // If there's a draining entry, start its drain timer
        if (drainingEntry) {
          startDrainTimer(drainingEntry);
        }
      }
    } catch (error) {
      if (!controller.signal.aborted) {
        logger.warn('Settling failed', {
          error,
          roomname: entry.roomname,
        });
        // Entry remains in settling state on error
      }
    }
  };

  /**
   * Attach provider event handlers for state tracking
   */
  const attachProviderHandlers = (entry: ChannelEntry): (() => void) => {
    const statusHandler = (event: { status: string }) => {
      logger.debug('Provider status change', {
        roomname: entry.roomname,
        status: event.status,
        currentState: entry.state,
      });

      // Transition from connecting to settling when connected
      if (event.status === 'connected' && entry.state === 'connecting') {
        updateEntryState(entry, 'settling');

        // Start settling process
        settlingController = new AbortController();
        waitForSettled(entry, settlingController);
      }
    };

    entry.provider.on('status', statusHandler);

    return () => {
      entry.provider.off('status', statusHandler);
    };
  };

  /**
   * Create a new channel entry
   */
  const createEntry = (
    socket: Socket,
    roomname: string,
    joinParams: object
  ): ChannelEntry => {
    logger.debug('Creating new entry', { roomname });

    const ydoc = new YDoc();
    const awareness = new Awareness(ydoc);
    const provider = new PhoenixChannelProvider(socket, roomname, ydoc, {
      awareness,
      connect: true,
      params: joinParams,
    });

    const entry: ChannelEntry = {
      roomname,
      ydoc,
      provider,
      awareness,
      state: 'connecting',
      createdAt: Date.now(),
      settledAt: null,
    };

    // Attach handlers for state transitions
    attachProviderHandlers(entry);

    return entry;
  };

  /**
   * Migrate to a new channel
   */
  const migrate = async (
    socket: Socket,
    newRoomname: string,
    joinParams: object
  ): Promise<void> => {
    logger.debug('Starting migration', {
      from: currentEntry?.roomname,
      to: newRoomname,
    });

    // Create new entry
    const newEntry = createEntry(socket, newRoomname, joinParams);

    // Mark current entry as draining if it exists
    if (currentEntry) {
      logger.debug('Marking current entry as draining', {
        roomname: currentEntry.roomname,
      });

      updateEntryState(currentEntry, 'draining');
      drainingEntry = currentEntry;
    }

    // Set new entry as current
    currentEntry = newEntry;
    notify();

    // Wait for new entry to become active
    return new Promise<void>((resolve, reject) => {
      const checkActive = () => {
        if (newEntry.state === 'active') {
          unsubscribe();
          resolve();
        } else if (newEntry.state === 'destroyed') {
          unsubscribe();
          reject(new Error('Entry was destroyed before becoming active'));
        }
      };

      const unsubscribe = subscribe(checkActive);

      // Check immediately in case state already changed
      checkActive();
    });
  };

  /**
   * Get the current active entry
   */
  const getCurrentEntry = (): ChannelEntry | null => {
    return currentEntry;
  };

  /**
   * Get the draining entry
   */
  const getDrainingEntry = (): ChannelEntry | null => {
    return drainingEntry;
  };

  /**
   * Check if registry is transitioning
   */
  const isTransitioning = (): boolean => {
    return drainingEntry !== null;
  };

  /**
   * Destroy the registry and all managed resources
   */
  const destroy = (): void => {
    logger.debug('Destroying registry');

    // Cancel any pending timers
    if (drainTimer) {
      clearTimeout(drainTimer);
      drainTimer = null;
    }

    // Cancel settling
    if (settlingController) {
      settlingController.abort();
      settlingController = null;
    }

    // Destroy all entries
    if (currentEntry) {
      destroyEntry(currentEntry);
      currentEntry = null;
    }

    if (drainingEntry) {
      destroyEntry(drainingEntry);
      drainingEntry = null;
    }

    // Clear listeners
    listeners.clear();
  };

  return {
    migrate,
    getCurrentEntry,
    getDrainingEntry,
    isTransitioning,
    subscribe,
    destroy,
  };
};

export type ChannelRegistryInstance = ReturnType<typeof createChannelRegistry>;
