/**
 * Resource Managers
 *
 * Built-in resource managers for common channel types.
 */

import type { Socket as PhoenixSocket } from 'phoenix';
import { PhoenixChannelProvider } from 'y-phoenix-channel';
import { Awareness } from 'y-protocols/awareness';
import { Doc as YDoc } from 'yjs';

import _logger from '#/utils/logger';

import type { LocalUserData } from '../../types/awareness';

import type { ResourceManager } from './types';

const logger = _logger.ns('YjsResourceManager').seal();

/**
 * No-op resource manager for simple channels without resources
 *
 * Use this for channels that don't need Y.Doc, Awareness, or other
 * managed resources (e.g., AI assistant channels).
 */
export const noopResourceManager: ResourceManager<null> = {
  create: () => null,
  destroy: () => {},
};

/**
 * Interface for Yjs resources (Y.Doc, Provider, Awareness)
 */
export interface YjsResources {
  /** Y.Doc instance */
  ydoc: YDoc;

  /** Phoenix Channel Provider for Y.Doc sync */
  provider: PhoenixChannelProvider;

  /** Awareness protocol instance for presence */
  awareness: Awareness;
}

/**
 * Factory for creating Yjs resource managers
 *
 * Creates a resource manager that handles Y.Doc, PhoenixChannelProvider,
 * and Awareness lifecycle.
 *
 * @param socket - Phoenix socket instance
 * @param topic - Channel topic string
 * @param userData - Local user data for awareness (optional)
 * @returns ResourceManager for Yjs resources
 *
 * @example
 * ```typescript
 * const yjsManager = createYjsResourceManager(
 *   socket,
 *   'workflow:collaborate:123',
 *   { userId: '123', userName: 'Alice' }
 * );
 * ```
 */
export function createYjsResourceManager(
  socket: PhoenixSocket,
  topic: string,
  userData: LocalUserData | null
): ResourceManager<YjsResources> {
  return {
    create(_channel) {
      logger.debug('Creating Yjs resources', { topic });

      const ydoc = new YDoc();
      const awareness = new Awareness(ydoc);

      // Set local user state if provided
      if (userData) {
        awareness.setLocalStateField('user', userData);
      }

      const provider = new PhoenixChannelProvider(socket, topic, ydoc, {
        awareness,
        connect: false,
      });

      return { ydoc, provider, awareness };
    },

    destroy(resources) {
      logger.debug('Destroying Yjs resources');

      try {
        resources.provider.destroy();
        resources.awareness.destroy();
        resources.ydoc.destroy();
      } catch (error) {
        logger.warn('Error destroying Yjs resources', { error });
      }
    },

    async waitForSettled(resources, abortSignal) {
      logger.debug('Waiting for Yjs resources to settle');

      await Promise.all([
        waitForProviderSync(resources.provider, abortSignal),
        waitForFirstUpdate(resources.ydoc, resources.provider, abortSignal),
      ]);

      logger.debug('Yjs resources settled');
    },
  };
}

/**
 * Wait for provider to sync
 */
function waitForProviderSync(
  provider: PhoenixChannelProvider,
  abortSignal: AbortSignal
): Promise<void> {
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

    abortSignal.addEventListener('abort', () => {
      cleanup();
      resolve();
    });
  });
}

/**
 * Wait for first Y.Doc update from provider
 */
function waitForFirstUpdate(
  ydoc: YDoc,
  provider: PhoenixChannelProvider,
  abortSignal: AbortSignal
): Promise<void> {
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

    abortSignal.addEventListener('abort', () => {
      cleanup();
      resolve();
    });

    ydoc.on('update', handler);
  });
}
