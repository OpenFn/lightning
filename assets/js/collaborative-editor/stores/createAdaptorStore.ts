/**
 * # AdaptorStore
 *
 * This store implements the same pattern as WorkflowStore: useSyncExternalStore + Immer
 * for optimal performance and referential stability.
 *
 * ## Core Principles:
 * - Immer for referentially stable state updates
 * - Command Query Separation (CQS) for predictable state mutations
 * - Single source of truth for adaptor data
 * - Optimistic updates with error recovery
 *
 * ## Update Patterns:
 *
 * ### Pattern 1: Channel Message → Immer → Notify (Server Updates)
 * **When to use**: All server-initiated adaptor updates
 * **Flow**: Channel message → validate with Zod → Immer update → React notification
 * **Benefits**: Automatic validation, error handling, type safety
 *
 * ```typescript
 * // Example: Handle server adaptor list update
 * const handleAdaptorsUpdate = (rawData: unknown) => {
 *   const result = AdaptorsListSchema.safeParse(rawData);
 *   if (result.success) {
 *     state = produce(state, (draft) => {
 *       draft.adaptors = result.data;
 *       draft.lastUpdated = Date.now();
 *       draft.error = null;
 *     });
 *     notify();
 *   }
 * };
 * ```
 *
 * ### Pattern 2: Direct Immer → Notify (Local State)
 * **When to use**: Loading states, errors, local UI state
 * **Flow**: Direct Immer update → React notification
 * **Benefits**: Immediate response, simple implementation
 *
 * ```typescript
 * // Example: Set loading state
 * const setLoading = (loading: boolean) => {
 *   state = produce(state, (draft) => {
 *     draft.isLoading = loading;
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
 * 2. Open DevTools and select the "AdaptorStore" instance
 * 3. Perform actions in the app and watch them appear in DevTools
 *
 * **Note:** DevTools is automatically disabled in production builds.
 *
 * **Excluded from DevTools:**
 * None (all state is serializable)
 */

import { produce } from 'immer';
import type { PhoenixChannelProvider } from 'y-phoenix-channel';

import _logger from '#/utils/logger';

import { channelRequest } from '../hooks/useChannel';
import {
  type Adaptor,
  type AdaptorState,
  type AdaptorStore,
  type AdaptorsList,
  AdaptorsListSchema,
} from '../types/adaptor';

import { createWithSelector } from './common';
import { wrapStoreWithDevTools } from './devtools';

const logger = _logger.ns('AdaptorStore').seal();

// sorts adaptors coming into the adaptor store
// 1. sorts the versions for every adaptor
// 2. sorts the adaptors themselves by name
export function sortAdaptors(adaptors: AdaptorsList = []) {
  const sortedAdaptors: AdaptorsList = [];
  for (const adaptor of adaptors) {
    // spreading because it could be read-only.
    const versions = [...(adaptor.versions || [])].sort((a, b) =>
      b.version.localeCompare(a.version)
    );
    sortedAdaptors.push({ ...adaptor, versions });
  }
  return sortedAdaptors.sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * Creates an adaptor store instance with useSyncExternalStore + Immer pattern
 */
export const createAdaptorStore = (): AdaptorStore => {
  // Single Immer-managed state object (referentially stable)
  let state: AdaptorState = produce(
    {
      adaptors: [],
      projectAdaptors: [],
      isLoading: false,
      error: null,
      lastUpdated: null,
    } as AdaptorState,
    // No initial transformations needed
    draft => draft
  );

  const listeners = new Set<() => void>();

  // Redux DevTools integration
  const devtools = wrapStoreWithDevTools({
    name: 'AdaptorStore',
    excludeKeys: [], // All state is serializable
    maxAge: 100,
  });

  const notify = (actionName: string = 'stateChange') => {
    devtools.notifyWithAction(actionName, () => state);
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

  const getSnapshot = (): AdaptorState => state;

  // withSelector utility - creates memoized selectors for referential stability
  const withSelector = createWithSelector(getSnapshot);

  // =============================================================================
  // PATTERN 1: Channel Message → Immer → Notify (Server Updates)
  // =============================================================================

  /**
   * Handle adaptors list received from server
   * Validates data with Zod before updating state
   */
  const handleAdaptorsReceived = (rawData: unknown) => {
    const result = AdaptorsListSchema.safeParse(rawData);

    if (result.success) {
      const adaptors = sortAdaptors(result.data);

      state = produce(state, draft => {
        draft.adaptors = adaptors;
        draft.isLoading = false;
        draft.error = null;
        draft.lastUpdated = Date.now();
      });
      notify('handleAdaptorsReceived');
    } else {
      const errorMessage = `Invalid adaptors data: ${result.error.message}`;
      logger.error('Failed to parse adaptors data', {
        error: result.error,
        rawData,
      });

      state = produce(state, draft => {
        draft.isLoading = false;
        draft.error = errorMessage;
      });
      notify('adaptorsError');
    }
  };

  /**
   * Handle real-time adaptors update from server
   */
  const handleAdaptorsUpdated = (rawData: unknown) => {
    // Same validation logic as handleAdaptorsReceived
    handleAdaptorsReceived(rawData);
  };

  // =============================================================================
  // PATTERN 2: Direct Immer → Notify (Local State)
  // =============================================================================

  const setLoading = (loading: boolean) => {
    state = produce(state, draft => {
      draft.isLoading = loading;
    });
    notify('setLoading');
  };

  const setError = (error: string | null) => {
    state = produce(state, draft => {
      draft.error = error;
      draft.isLoading = false;
    });
    notify('setError');
  };

  const clearError = () => {
    state = produce(state, draft => {
      draft.error = null;
    });
    notify('clearError');
  };

  const setAdaptors = (adaptors: Adaptor[]) => {
    state = produce(state, draft => {
      draft.adaptors = sortAdaptors(adaptors);
      draft.lastUpdated = Date.now();
      draft.error = null;
    });
    notify('setAdaptors');
  };

  // =============================================================================
  // CHANNEL INTEGRATION
  // =============================================================================

  let channelProvider: PhoenixChannelProvider | null = null;

  /**
   * Connect to Phoenix channel provider for real-time updates
   */
  const connectChannel = (provider: PhoenixChannelProvider) => {
    channelProvider = provider;

    const adaptorsListHandler = (message: unknown) => {
      logger.debug('Received adaptors_list message', message);
      handleAdaptorsReceived(message);
    };

    const adaptorsUpdatedHandler = (message: unknown) => {
      logger.debug('Received adaptors_updated message', message);
      handleAdaptorsUpdated(message);
    };

    // Set up channel listeners
    if (provider.channel) {
      provider.channel.on('adaptors_updated', adaptorsUpdatedHandler);
    }

    devtools.connect();

    void requestAdaptors();
    void requestProjectAdaptors();

    return () => {
      devtools.disconnect();
      if (provider.channel) {
        provider.channel.off('adaptors_list', adaptorsListHandler);
        provider.channel.off('adaptors_updated', adaptorsUpdatedHandler);
      }
      channelProvider = null;
    };
  };

  /**
   * Request adaptors from server via channel
   */
  const requestAdaptors = async (): Promise<void> => {
    if (!channelProvider?.channel) {
      logger.warn('Cannot request adaptors - no channel connected');
      setError('No connection available');
      return;
    }

    setLoading(true);
    clearError();

    try {
      const response = await channelRequest<{ adaptors: unknown }>(
        channelProvider.channel,
        'request_adaptors',
        {}
      );

      if (response.adaptors) {
        handleAdaptorsReceived(response.adaptors);
      }
    } catch (error) {
      logger.error('Adaptor request failed', error);
      setError(
        `Failed to request adaptors: ${error instanceof Error ? error.message : 'Unknown error'}`
      );
    }
  };

  /**
   * Request project adaptors from server via channel
   */
  const requestProjectAdaptors = async (): Promise<void> => {
    if (!channelProvider?.channel) {
      logger.warn('Cannot request project adaptors - no channel connected');
      setError('No connection available');
      return;
    }

    setLoading(true);
    clearError();

    try {
      logger.debug('Requesting project adaptors');
      const response = await channelRequest(
        channelProvider.channel,
        'request_project_adaptors',
        {}
      );

      if (response && typeof response === 'object') {
        const { project_adaptors, all_adaptors } = response as {
          project_adaptors: unknown;
          all_adaptors: unknown;
        };

        const projectResult = AdaptorsListSchema.safeParse(project_adaptors);
        const allResult = AdaptorsListSchema.safeParse(all_adaptors);

        if (projectResult.success && allResult.success) {
          state = produce(state, draft => {
            draft.projectAdaptors = sortAdaptors(projectResult.data);
            draft.adaptors = sortAdaptors(allResult.data);
            draft.isLoading = false;
            draft.error = null;
          });
          notify('requestProjectAdaptors');
        } else {
          const errorMessage = 'Invalid project adaptors data';
          logger.error(errorMessage, { projectResult, allResult });
          setError(errorMessage);
        }
      }
    } catch (error) {
      logger.error('Project adaptors request failed', error);
      setError('Failed to request project adaptors');
    }
  };

  // =============================================================================
  // QUERY HELPERS
  // =============================================================================

  const findAdaptorByName = (name: string): Adaptor | null => {
    return state.adaptors.find(adaptor => adaptor.name === name) || null;
  };

  const getLatestVersion = (adaptorName: string): string | null => {
    const adaptor = findAdaptorByName(adaptorName);
    return adaptor?.latest || null;
  };

  const getVersions = (adaptorName: string) => {
    const adaptor = findAdaptorByName(adaptorName);
    return adaptor?.versions || [];
  };

  // =============================================================================
  // PUBLIC INTERFACE
  // =============================================================================

  return {
    // Core store interface
    subscribe,
    getSnapshot,
    withSelector,

    // Commands (CQS pattern)
    requestAdaptors,
    requestProjectAdaptors,
    setAdaptors,
    setLoading,
    setError,
    clearError,

    // Queries (CQS pattern)
    findAdaptorByName,
    getLatestVersion,
    getVersions,

    // Internal methods (not part of public AdaptorStore interface)
    _connectChannel: connectChannel,
    // Test helper to set project adaptors directly
    _setProjectAdaptors: (adaptors: Adaptor[]) => {
      state = produce(state, draft => {
        draft.projectAdaptors = sortAdaptors(adaptors);
      });
      notify('_setProjectAdaptors');
    },
  };
};

export type AdaptorStoreInstance = ReturnType<typeof createAdaptorStore>;
