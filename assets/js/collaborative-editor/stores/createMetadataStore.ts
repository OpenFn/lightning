/**
 * # MetadataStore
 *
 * This store implements the same pattern as AdaptorStore: useSyncExternalStore + Immer
 * for optimal performance and referential stability.
 *
 * ## Core Principles:
 * - Immer for referentially stable state updates
 * - Command Query Separation (CQS) for predictable state mutations
 * - Per-job metadata caching to prevent redundant fetches
 * - Optimistic updates with error recovery
 *
 * ## Update Patterns:
 *
 * ### Pattern 1: Channel Message → Immer → Notify (Server Updates)
 * **When to use**: All server-initiated metadata updates
 * **Flow**: Channel message → validate with Zod → Immer update → React notification
 * **Benefits**: Automatic validation, error handling, type safety
 *
 * ```typescript
 * // Example: Handle server metadata response
 * const handleMetadataReceived = (rawData: unknown) => {
 *   const result = MetadataResponseSchema.safeParse(rawData);
 *   if (result.success) {
 *     state = produce(state, (draft) => {
 *       const jobState = draft.jobs.get(job_id) || createEmptyJobState();
 *       jobState.metadata = result.data.metadata;
 *       draft.jobs.set(job_id, jobState);
 *     });
 *     notify();
 *   }
 * };
 * ```
 *
 * ### Pattern 2: Direct Immer → Notify (Local State)
 * **When to use**: Loading states, errors, cache clearing
 * **Flow**: Direct Immer update → React notification
 * **Benefits**: Immediate response, simple implementation
 *
 * ```typescript
 * // Example: Set loading state for a job
 * const setLoading = (jobId: string) => {
 *   state = produce(state, (draft) => {
 *     const jobState = draft.jobs.get(jobId) || createEmptyJobState();
 *     jobState.isLoading = true;
 *     draft.jobs.set(jobId, jobState);
 *   });
 *   notify();
 * };
 * ```
 *
 * ## Architecture Notes:
 * - All validation happens at runtime with Zod schemas
 * - Channel messaging is handled externally (SessionProvider)
 * - Store provides both commands and queries following CQS pattern
 * - withSelector utility provides memoized selectors for performance
 * - Per-job caching with Map<jobId, JobMetadataState> structure
 * - Cache key comparison prevents redundant fetches
 */

/**
 * ## Redux DevTools Integration
 *
 * This store integrates with Redux DevTools for debugging in
 * development and test environments.
 *
 * **Features:**
 * - Real-time state inspection
 * - Action history with timestamps
 * - Time-travel debugging (jump to previous states)
 * - State export/import for reproducing bugs
 *
 * **Usage:**
 * 1. Install Redux DevTools browser extension
 * 2. Open DevTools and select the "MetadataStore" instance
 * 3. Perform actions in the app and watch them appear in DevTools
 *
 * **Note:** DevTools is automatically disabled in production builds.
 *
 * **Excluded from DevTools:**
 * - jobs (Map is not serializable - converted to object for DevTools)
 */

import { produce } from 'immer';
import type { PhoenixChannelProvider } from 'y-phoenix-channel';

import _logger from '#/utils/logger';

import { channelRequest } from '../hooks/useChannel';
import {
  type JobMetadataState,
  type Metadata,
  type MetadataState,
  type MetadataStore,
  MetadataResponseSchema,
} from '../types/metadata';

import { createWithSelector } from './common';
import { wrapStoreWithDevTools } from './devtools';

const logger = _logger.ns('MetadataStore').seal();

/**
 * Creates an empty job metadata state
 */
const createEmptyJobState = (): JobMetadataState => ({
  metadata: null,
  error: null,
  isLoading: false,
  lastFetched: null,
  cacheKey: null,
});

/**
 * Creates a metadata store instance with useSyncExternalStore + Immer pattern
 */
export const createMetadataStore = (): MetadataStore => {
  // Single Immer-managed state object (referentially stable)
  let state: MetadataState = produce(
    {
      jobs: new Map(),
    } as MetadataState,
    // No initial transformations needed
    draft => draft
  );

  const listeners = new Set<() => void>();

  // Redux DevTools integration
  const devtools = wrapStoreWithDevTools({
    name: 'MetadataStore',
    excludeKeys: ['jobs'], // Map is not serializable
    maxAge: 100,
  });

  const notify = (actionName: string = 'stateChange') => {
    // Convert Map to object for DevTools
    const serializableState = {
      jobs: Object.fromEntries(state.jobs),
    };
    devtools.notifyWithAction(actionName, () => serializableState);
    listeners.forEach(listener => {
      listener();
    });
  };

  // =============================================================================
  // CORE STORE INTERFACE
  // =============================================================================

  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  const getSnapshot = (): MetadataState => state;

  // withSelector utility - creates memoized selectors for referential stability
  const withSelector = createWithSelector(getSnapshot);

  // =============================================================================
  // PATTERN 1: Channel Message → Immer → Notify (Server Updates)
  // =============================================================================

  /**
   * Handle metadata response received from server
   * Validates data with Zod before updating state
   */
  const handleMetadataReceived = (rawData: unknown) => {
    const result = MetadataResponseSchema.safeParse(rawData);

    if (result.success) {
      const { job_id, metadata } = result.data;

      state = produce(state, draft => {
        const jobState = draft.jobs.get(job_id) || createEmptyJobState();

        if ('error' in metadata && typeof metadata.error === 'string') {
          jobState.error = metadata.error;
          jobState.metadata = null;
        } else {
          jobState.metadata = metadata as Metadata;
          jobState.error = null;
          jobState.lastFetched = Date.now();
        }

        jobState.isLoading = false;
        draft.jobs.set(job_id, jobState);
      });

      notify('handleMetadataReceived');
    } else {
      logger.error('Failed to parse metadata response', {
        error: result.error,
        rawData,
      });

      // We don't know which job this was for, so we can't update the specific job state
      logger.warn('Cannot update job state without job_id in response');
    }
  };

  // =============================================================================
  // PATTERN 2: Direct Immer → Notify (Local State Updates)
  // =============================================================================

  /**
   * Set error for a specific job
   */
  const setError = (jobId: string, error: string) => {
    state = produce(state, draft => {
      const jobState = draft.jobs.get(jobId) || createEmptyJobState();
      jobState.error = error;
      jobState.isLoading = false;
      draft.jobs.set(jobId, jobState);
    });
    notify('setError');
  };

  // =============================================================================
  // CHANNEL INTEGRATION
  // =============================================================================

  let channelProvider: PhoenixChannelProvider | null = null;

  /**
   * Generate cache key for deduplication
   */
  const getCacheKey = (
    adaptor: string,
    credentialId: string | null
  ): string => {
    return `${adaptor}:${credentialId || 'none'}`;
  };

  /**
   * Connect to Phoenix channel provider for real-time updates
   */
  const connectChannel = (provider: PhoenixChannelProvider) => {
    channelProvider = provider;

    const metadataHandler = (message: unknown) => {
      logger.debug('Received metadata message', message);
      handleMetadataReceived(message);
    };

    // Set up channel listeners
    if (provider.channel) {
      provider.channel.on('request_metadata', metadataHandler);
    }

    devtools.connect();

    return () => {
      devtools.disconnect();
      if (provider.channel) {
        provider.channel.off('request_metadata', metadataHandler);
      }
      channelProvider = null;
    };
  };

  /**
   * Request metadata for a specific job from server via channel
   */
  const requestMetadata = async (
    jobId: string,
    adaptor: string,
    credentialId: string | null
  ): Promise<void> => {
    if (!channelProvider?.channel) {
      logger.warn('Cannot request metadata - no channel connected');
      setError(jobId, 'No connection available');
      return;
    }

    const newCacheKey = getCacheKey(adaptor, credentialId);
    const currentJobState = state.jobs.get(jobId);

    // Skip if already loading
    if (currentJobState?.isLoading) {
      logger.debug('Metadata already loading for job', { jobId });
      return;
    }

    // Skip if cache is valid
    if (
      currentJobState?.cacheKey === newCacheKey &&
      currentJobState?.metadata
    ) {
      logger.debug('Using cached metadata', { jobId, cacheKey: newCacheKey });
      return;
    }

    // Set loading state and update cache key
    state = produce(state, draft => {
      const jobState = draft.jobs.get(jobId) || createEmptyJobState();
      jobState.isLoading = true;
      jobState.error = null;
      jobState.cacheKey = newCacheKey;
      draft.jobs.set(jobId, jobState);
    });
    notify('requestMetadata:start');

    try {
      logger.debug('Requesting metadata for job', {
        jobId,
        adaptor,
        credentialId,
      });
      await channelRequest(channelProvider.channel, 'request_metadata', {
        job_id: jobId,
      });
      // Response will be handled by handleMetadataReceived
    } catch (error) {
      logger.error('Metadata request failed', error);
      setError(jobId, error instanceof Error ? error.message : 'Unknown error');
    }
  };

  // =============================================================================
  // COMMANDS
  // =============================================================================

  /**
   * Clear metadata for a specific job
   */
  const clearMetadata = (jobId: string) => {
    state = produce(state, draft => {
      draft.jobs.delete(jobId);
    });
    notify('clearMetadata');
  };

  /**
   * Clear all metadata
   */
  const clearAllMetadata = () => {
    state = produce(state, draft => {
      draft.jobs.clear();
    });
    notify('clearAllMetadata');
  };

  // =============================================================================
  // QUERIES
  // =============================================================================

  /**
   * Get metadata for a specific job
   */
  const getMetadataForJob = (jobId: string): Metadata | null => {
    return state.jobs.get(jobId)?.metadata || null;
  };

  /**
   * Check if metadata is loading for a specific job
   */
  const isLoadingForJob = (jobId: string): boolean => {
    return state.jobs.get(jobId)?.isLoading || false;
  };

  /**
   * Get error for a specific job
   */
  const getErrorForJob = (jobId: string): string | null => {
    return state.jobs.get(jobId)?.error || null;
  };

  // =============================================================================
  // PUBLIC API
  // =============================================================================

  return {
    // Core interface
    subscribe,
    getSnapshot,
    withSelector,

    // Commands
    requestMetadata,
    clearMetadata,
    clearAllMetadata,

    // Queries
    getMetadataForJob,
    isLoadingForJob,
    getErrorForJob,

    // Internals
    _connectChannel: connectChannel,
  };
};

export type MetadataStoreInstance = ReturnType<typeof createMetadataStore>;
