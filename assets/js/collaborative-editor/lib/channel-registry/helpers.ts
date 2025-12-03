/**
 * Channel Registry Helpers
 *
 * Reusable helper functions for channel lifecycle management.
 * These functions are pure or have isolated side effects for testability.
 */

import type { Channel as PhoenixChannel } from 'phoenix';

import _logger from '#/utils/logger';

import type { ChannelEntry, ChannelState, ResourceManager } from './types';

const logger = _logger.ns('ChannelRegistryHelpers').seal();

/**
 * Valid state transitions map
 */
const VALID_TRANSITIONS: Record<ChannelState, ChannelState[]> = {
  connecting: ['settling', 'active', 'destroyed'],
  settling: ['active', 'destroyed'],
  active: ['draining', 'destroyed'],
  draining: ['destroyed'],
  destroyed: [],
};

/**
 * Transition channel entry to a new state with validation
 *
 * @param entry - Channel entry to transition
 * @param newState - Target state
 * @returns True if transition was valid and performed, false otherwise
 */
export function transitionState<TResources>(
  entry: ChannelEntry<TResources>,
  newState: ChannelState
): boolean {
  const currentState = entry.state;

  // Check if transition is valid
  if (!VALID_TRANSITIONS[currentState].includes(newState)) {
    logger.warn('Invalid state transition attempted', {
      topic: entry.topic,
      from: currentState,
      to: newState,
    });
    return false;
  }

  logger.debug('State transition', {
    topic: entry.topic,
    from: currentState,
    to: newState,
  });

  entry.state = newState;
  return true;
}

/**
 * Create a new channel entry
 *
 * @param topic - Channel topic
 * @param channel - Phoenix Channel instance
 * @param subscriberId - ID of initial subscriber
 * @param resources - Initial resources (null if not yet created)
 * @returns Created channel entry
 */
export function createChannelEntry<TResources>(
  topic: string,
  channel: PhoenixChannel,
  subscriberId: string,
  resources: TResources | null
): ChannelEntry<TResources> {
  logger.debug('Creating channel entry', { topic, subscriberId });

  return {
    topic,
    state: 'connecting',
    subscribers: new Set([subscriberId]),
    channel,
    resources,
    cleanupTimer: null,
    settlingAbortController: null,
    error: null,
  };
}

/**
 * Schedule cleanup with delay
 *
 * @param entry - Channel entry to schedule cleanup for
 * @param delayMs - Delay in milliseconds
 * @param cleanupFn - Function to call after delay
 */
export function scheduleCleanup(
  entry: ChannelEntry<unknown>,
  delayMs: number,
  cleanupFn: () => void
): void {
  // Cancel existing timer if any
  if (entry.cleanupTimer) {
    clearTimeout(entry.cleanupTimer);
  }

  logger.debug('Scheduling cleanup', {
    topic: entry.topic,
    delayMs,
  });

  entry.cleanupTimer = setTimeout(() => {
    logger.debug('Cleanup timer elapsed', { topic: entry.topic });
    entry.cleanupTimer = null;
    cleanupFn();
  }, delayMs);
}

/**
 * Cancel pending cleanup timer
 *
 * @param entry - Channel entry to cancel cleanup for
 */
export function cancelCleanup(entry: ChannelEntry<unknown>): void {
  if (entry.cleanupTimer) {
    logger.debug('Canceling cleanup timer', { topic: entry.topic });
    clearTimeout(entry.cleanupTimer);
    entry.cleanupTimer = null;
  }
}

/**
 * Start settling phase with timeout
 *
 * @param entry - Channel entry to settle
 * @param resourceManager - Resource manager with waitForSettled
 * @param timeoutMs - Timeout in milliseconds
 * @param onComplete - Called when settling completes successfully
 * @returns Promise that resolves when settling completes or is aborted
 */
export async function startSettling<TResources>(
  entry: ChannelEntry<TResources>,
  resourceManager: ResourceManager<TResources>,
  timeoutMs: number,
  onComplete: () => void
): Promise<void> {
  if (!resourceManager.waitForSettled) {
    logger.warn('Resource manager has no waitForSettled method', {
      topic: entry.topic,
    });
    return;
  }

  if (!entry.resources) {
    logger.warn('Cannot settle: no resources available', {
      topic: entry.topic,
    });
    return;
  }

  // Create abort controller for this settling phase
  entry.settlingAbortController = new AbortController();
  const controller = entry.settlingAbortController;

  logger.debug('Starting settling phase', {
    topic: entry.topic,
    timeoutMs,
  });

  try {
    // Create timeout promise
    const timeoutPromise = new Promise<void>((_, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error(`Settling timeout after ${timeoutMs}ms`));
      }, timeoutMs);

      controller.signal.addEventListener('abort', () => {
        clearTimeout(timeout);
      });
    });

    // Race between settling and timeout
    await Promise.race([
      resourceManager.waitForSettled(entry.resources, controller.signal),
      timeoutPromise,
    ]);

    // If not aborted, call completion handler
    if (!controller.signal.aborted) {
      logger.debug('Settling completed successfully', {
        topic: entry.topic,
      });
      onComplete();
    }
  } catch (error) {
    if (!controller.signal.aborted) {
      logger.warn('Settling failed', {
        topic: entry.topic,
        error: error instanceof Error ? error.message : String(error),
      });
      entry.error = `Settling failed: ${
        error instanceof Error ? error.message : String(error)
      }`;
    }
  } finally {
    entry.settlingAbortController = null;
  }
}

/**
 * Join channel and handle responses
 *
 * @param entry - Channel entry to join
 * @param onSuccess - Called on successful join
 * @param onError - Called on join error
 */
export function joinChannel(
  entry: ChannelEntry<unknown>,
  onSuccess: (response: unknown) => void,
  onError: (error: unknown) => void
): void {
  logger.debug('Joining channel', { topic: entry.topic });

  // Type assertion: Phoenix Channel type doesn't include join() in types
  // but it's available at runtime
  const channel = entry.channel as PhoenixChannel & {
    join(): {
      receive(
        status: 'ok',
        callback: (response: unknown) => void
      ): {
        receive(
          status: 'error',
          callback: (error: unknown) => void
        ): {
          receive(status: 'timeout', callback: () => void): void;
        };
      };
    };
  };

  channel
    .join()
    .receive('ok', response => {
      logger.debug('Channel joined successfully', {
        topic: entry.topic,
      });
      onSuccess(response);
    })
    .receive('error', error => {
      logger.warn('Channel join failed', {
        topic: entry.topic,
        error,
      });
      entry.error = `Join failed: ${JSON.stringify(error)}`;
      onError(error);
    })
    .receive('timeout', () => {
      logger.warn('Channel join timeout', { topic: entry.topic });
      entry.error = 'Join timeout';
      onError(new Error('Join timeout'));
    });
}

/**
 * Leave channel and cleanup resources
 *
 * @param entry - Channel entry to destroy
 * @param resourceManager - Resource manager or null if no resources
 */
export function destroyEntry<TResources>(
  entry: ChannelEntry<TResources>,
  resourceManager: ResourceManager<TResources> | null
): void {
  logger.debug('Destroying entry', { topic: entry.topic });

  // Cancel any pending operations
  cancelCleanup(entry);
  if (entry.settlingAbortController) {
    entry.settlingAbortController.abort();
    entry.settlingAbortController = null;
  }

  // Transition to destroyed state
  transitionState(entry, 'destroyed');

  // Destroy resources if manager provided
  if (resourceManager && entry.resources) {
    try {
      resourceManager.destroy(entry.resources);
    } catch (error) {
      logger.warn('Error destroying resources', {
        topic: entry.topic,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  // Leave channel
  try {
    // Type assertion: Phoenix Channel type doesn't include leave() in types
    // but it's available at runtime
    const channel = entry.channel as PhoenixChannel & {
      leave(): void;
    };
    channel.leave();
  } catch (error) {
    logger.warn('Error leaving channel', {
      topic: entry.topic,
      error: error instanceof Error ? error.message : String(error),
    });
  }

  // Clear subscribers
  entry.subscribers.clear();
}
