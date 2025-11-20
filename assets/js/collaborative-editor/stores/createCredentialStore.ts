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
 * 2. Open DevTools and select the "CredentialStore" instance
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
  type CredentialState,
  type CredentialStore,
  type CredentialWithType,
  type ProjectCredential,
  type KeychainCredential,
  CredentialsListSchema,
} from '../types/credential';

import { createWithSelector } from './common';
import { wrapStoreWithDevTools } from './devtools';

const logger = _logger.ns('CredentialStore').seal();

/**
 * Creates an credential store instance with useSyncExternalStore + Immer pattern
 */
export const createCredentialStore = (): CredentialStore => {
  // Single Immer-managed state object (referentially stable)
  let state: CredentialState = produce(
    {
      projectCredentials: [],
      keychainCredentials: [],
      isLoading: false,
      error: null,
      lastUpdated: null,
    } as CredentialState,
    // No initial transformations needed
    draft => draft
  );

  const listeners = new Set<() => void>();

  // Redux DevTools integration
  const devtools = wrapStoreWithDevTools({
    name: 'CredentialStore',
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

  const getSnapshot = (): CredentialState => state;

  // withSelector utility - creates memoized selectors for referential stability
  const withSelector = createWithSelector(getSnapshot);

  // =============================================================================
  // QUERIES (CQS pattern - read-only operations)
  // =============================================================================

  /**
   * Find a credential by ID
   * For ProjectCredentials: checks both 'id' and 'project_credential_id'
   * For KeychainCredentials: checks 'id'
   * Returns credential with type discriminator
   */
  const findCredentialById = (
    searchId: string | null
  ): CredentialWithType | null => {
    if (!searchId) return null;

    // Check project credentials (match either id or project_credential_id)
    const projectCred = state.projectCredentials.find(
      c => c.id === searchId || c.project_credential_id === searchId
    );
    if (projectCred) {
      return { ...projectCred, type: 'project' };
    }

    // Check keychain credentials (match id)
    const keychainCred = state.keychainCredentials.find(c => c.id === searchId);
    if (keychainCred) {
      return { ...keychainCred, type: 'keychain' };
    }

    return null;
  };

  /**
   * Check if a credential exists by ID
   */
  const credentialExists = (searchId: string | null): boolean => {
    return findCredentialById(searchId) !== null;
  };

  /**
   * Get the ID used for credential selection
   * (project_credential_id for project creds, id for keychain)
   */
  const getCredentialId = (
    cred: ProjectCredential | KeychainCredential
  ): string => {
    return 'project_credential_id' in cred
      ? cred.project_credential_id
      : cred.id;
  };

  // =============================================================================
  // PATTERN 1: Channel Message → Immer → Notify (Server Updates)
  // =============================================================================

  /**
   * Handle credentials list received from server
   * Validates data with Zod before updating state
   */
  const handleCredentialsReceived = (rawData: unknown) => {
    const result = CredentialsListSchema.safeParse(rawData);

    if (result.success) {
      const credentials = result.data;

      credentials.project_credentials.sort((a, b) =>
        a.name.localeCompare(b.name)
      );
      credentials.keychain_credentials.sort((a, b) =>
        a.name.localeCompare(b.name)
      );

      state = produce(state, draft => {
        draft.projectCredentials = credentials.project_credentials;
        draft.keychainCredentials = credentials.keychain_credentials;
        draft.isLoading = false;
        draft.error = null;
        draft.lastUpdated = Date.now();
      });
      notify('handleCredentialsReceived');
    } else {
      const errorMessage = `Invalid credentials data: ${result.error.message}`;
      logger.error('Failed to parse credentials data', {
        error: result.error,
        rawData,
      });

      state = produce(state, draft => {
        draft.isLoading = false;
        draft.error = errorMessage;
      });
      notify('credentialsError');
    }
  };

  /**
   * Handle real-time credentials update from server
   */
  const handleCredentialsUpdated = (rawData: unknown) => {
    // Same validation logic as handleCredentialsReceived
    handleCredentialsReceived(rawData);
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

  // =============================================================================
  // CHANNEL INTEGRATION
  // =============================================================================

  let _channelProvider: PhoenixChannelProvider | null = null;

  /**
   * Connect to Phoenix channel provider for real-time updates
   */
  const _connectChannel = (channelProvider: PhoenixChannelProvider) => {
    _channelProvider = channelProvider;
    const channel = channelProvider.channel;

    // Listen for credential-related channel messages
    const credentialsListHandler = (message: unknown) => {
      logger.debug('Received credentials_list message', message);
      handleCredentialsReceived(message);
    };

    const credentialsUpdatedHandler = (message: unknown) => {
      logger.debug('Received credentials_updated message', message);
      handleCredentialsUpdated(message);
    };

    // Set up channel listeners
    if (channel) {
      channel.on('credentials_list', credentialsListHandler);
      channel.on('credentials_updated', credentialsUpdatedHandler);
    }

    devtools.connect();

    void requestCredentials();

    return () => {
      devtools.disconnect();
      if (channel) {
        channel.off('credentials_list', credentialsListHandler);
        channel.off('credentials_updated', credentialsUpdatedHandler);
      }
      _channelProvider = null;
    };
  };

  /**
   * Request credentials from server via channel
   */
  const requestCredentials = async (): Promise<void> => {
    if (!_channelProvider?.channel) {
      logger.warn('Cannot request credentials - no channel connected');
      setError('No connection available');
      return;
    }

    setLoading(true);
    clearError();

    try {
      logger.debug('Requesting credentials');
      const response = await channelRequest<{ credentials: unknown }>(
        _channelProvider.channel,
        'request_credentials',
        {}
      );

      if (response.credentials) {
        handleCredentialsReceived(response.credentials);
      }
    } catch (error) {
      logger.error('Credential request failed', error);
      setError('Failed to request credentials');
    }
  };

  // =============================================================================
  // PUBLIC INTERFACE
  // =============================================================================

  return {
    // Core store interface
    subscribe,
    getSnapshot,
    withSelector,

    // Queries (CQS pattern)
    findCredentialById,
    credentialExists,
    getCredentialId,

    // Commands (CQS pattern)
    requestCredentials,
    setLoading,
    setError,
    clearError,

    // Internal methods (not part of public CredentialStore interface)
    _connectChannel,
  };
};

export type CredentialStoreInstance = ReturnType<typeof createCredentialStore>;
