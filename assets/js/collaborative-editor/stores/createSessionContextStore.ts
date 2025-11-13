/**
 * # SessionContextStore
 *
 * This store implements the same pattern as WorkflowStore: useSyncExternalStore + Immer
 * for optimal performance and referential stability.
 *
 * ## Core Principles:
 * - Immer for referentially stable state updates
 * - Command Query Separation (CQS) for predictable state mutations
 * - Single source of truth for session context data
 * - Optimistic updates with error recovery
 *
 * ## Update Patterns:
 *
 * ### Pattern 1: Channel Message → Zod → Immer → Notify (Server Updates)
 * **When to use**: All server-initiated session context updates
 * **Flow**: Channel message → validate with Zod → Immer update → React notification
 * **Benefits**: Automatic validation, error handling, type safety
 *
 * ```typescript
 * // Example: Handle server session context update
 * const handleSessionContextReceived = (rawData: unknown) => {
 *   const result = SessionContextResponseSchema.safeParse(rawData);
 *   if (result.success) {
 *     state = produce(state, (draft) => {
 *       draft.user = result.data.user;
 *       draft.project = result.data.project;
 *       draft.config = result.data.config;
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
 * 2. Open DevTools and select the "SessionContextStore" instance
 * 3. Perform actions in the app and watch them appear in DevTools
 *
 * **Note:** DevTools is automatically disabled in production builds.
 *
 * **Excluded from DevTools:**
 * None (all state is serializable)
 */

import { produce } from 'immer';
import type { PhoenixChannelProvider } from 'y-phoenix-channel';
import { z } from 'zod';

import _logger from '#/utils/logger';

import { channelRequest } from '../hooks/useChannel';
import {
  type SessionContextState,
  type SessionContextStore,
  SessionContextResponseSchema,
  WebhookAuthMethodSchema,
} from '../types/sessionContext';

import { createWithSelector } from './common';
import { wrapStoreWithDevTools } from './devtools';

const logger = _logger.ns('SessionContextStore').seal();

/**
 * Creates a session context store instance with useSyncExternalStore + Immer pattern
 */
export const createSessionContextStore = (
  isNewWorkflow: boolean = false
): SessionContextStore => {
  // Single Immer-managed state object (referentially stable)
  let state: SessionContextState = produce(
    {
      user: null,
      project: null,
      config: null,
      permissions: null,
      latestSnapshotLockVersion: null,
      projectRepoConnection: null,
      webhookAuthMethods: [],
      isNewWorkflow,
      isLoading: false,
      error: null,
      lastUpdated: null,
    } as SessionContextState,
    // No initial transformations needed
    draft => draft
  );

  const listeners = new Set<() => void>();

  // Redux DevTools integration
  const devtools = wrapStoreWithDevTools({
    name: 'SessionContextStore',
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

  const getSnapshot = (): SessionContextState => state;

  // withSelector utility - creates memoized selectors for referential stability
  const withSelector = createWithSelector(getSnapshot);

  // =============================================================================
  // PATTERN 1: Channel Message → Zod → Immer → Notify (Server Updates)
  // =============================================================================

  /**
   * Handle session context received from server
   * Validates data with Zod before updating state
   */
  const handleSessionContextReceived = (rawData: unknown) => {
    const result = SessionContextResponseSchema.safeParse(rawData);

    if (result.success) {
      const sessionContext = result.data;

      state = produce(state, draft => {
        draft.user = sessionContext.user;
        draft.project = sessionContext.project;
        draft.config = sessionContext.config;
        draft.permissions = sessionContext.permissions;
        draft.latestSnapshotLockVersion =
          sessionContext.latest_snapshot_lock_version;
        draft.projectRepoConnection = sessionContext.project_repo_connection;
        draft.webhookAuthMethods = sessionContext.webhook_auth_methods;
        draft.isLoading = false;
        draft.error = null;
        draft.lastUpdated = Date.now();
      });
      notify('handleSessionContextReceived');
    } else {
      const errorMessage = `Invalid session context data: ${result.error.message}`;
      logger.error('Failed to parse session context data', {
        error: result.error,
        rawData,
      });

      state = produce(state, draft => {
        draft.isLoading = false;
        draft.error = errorMessage;
      });
      notify('sessionContextError');
    }
  };

  /**
   * Handle real-time session context update from server
   */
  const handleSessionContextUpdated = (rawData: unknown) => {
    // Same validation logic as handleSessionContextReceived
    handleSessionContextReceived(rawData);
  };

  /**
   * Handle webhook auth methods update from server
   * Updates only the webhook auth methods without affecting other session context
   */
  const handleWebhookAuthMethodsUpdated = (rawData: unknown) => {
    // Validate the webhook_auth_methods array
    if (
      typeof rawData === 'object' &&
      rawData !== null &&
      'webhook_auth_methods' in rawData
    ) {
      const result = z
        .array(WebhookAuthMethodSchema)
        .safeParse(
          (rawData as { webhook_auth_methods: unknown }).webhook_auth_methods
        );

      if (result.success) {
        state = produce(state, draft => {
          draft.webhookAuthMethods = result.data;
          draft.lastUpdated = Date.now();
        });
        notify('handleWebhookAuthMethodsUpdated');
      } else {
        logger.error('Failed to parse webhook auth methods data', {
          error: result.error,
          rawData,
        });
      }
    }
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

  /**
   * Update latest snapshot lock version
   * Called when workflow is saved and backend returns new lock version
   */
  const setLatestSnapshotLockVersion = (lockVersion: number) => {
    state = produce(state, draft => {
      draft.latestSnapshotLockVersion = lockVersion;
      draft.lastUpdated = Date.now();
    });
    notify('setLatestSnapshotLockVersion');
  };

  /**
   * Clear isNewWorkflow flag
   * Called after first successful save of a new workflow
   */
  const clearIsNewWorkflow = () => {
    state = produce(state, draft => {
      draft.isNewWorkflow = false;
    });
    notify('clearIsNewWorkflow');
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

    // Listen for session-context-related channel messages
    const sessionContextHandler = (message: unknown) => {
      logger.debug('Received session_context message', message);
      handleSessionContextReceived(message);
    };

    const sessionContextUpdatedHandler = (message: unknown) => {
      logger.debug('Received session_context_updated message', message);
      handleSessionContextUpdated(message);
    };

    const workflowSavedHandler = (message: unknown) => {
      logger.debug('Received workflow_saved message', message);
      // Type guard for workflow saved message
      if (
        typeof message === 'object' &&
        message !== null &&
        'latest_snapshot_lock_version' in message &&
        typeof (message as { latest_snapshot_lock_version: unknown })
          .latest_snapshot_lock_version === 'number'
      ) {
        const lockVersion = (
          message as { latest_snapshot_lock_version: number }
        ).latest_snapshot_lock_version;
        logger.debug('Workflow saved - updating lock version', lockVersion);
        setLatestSnapshotLockVersion(lockVersion);
      }
    };

    const webhookAuthMethodsUpdatedHandler = (message: unknown) => {
      logger.debug('Received webhook_auth_methods_updated message', message);
      handleWebhookAuthMethodsUpdated(message);
    };

    // Set up channel listeners
    if (channel) {
      channel.on('session_context', sessionContextHandler);
      channel.on('session_context_updated', sessionContextUpdatedHandler);
      channel.on('workflow_saved', workflowSavedHandler);
      channel.on(
        'webhook_auth_methods_updated',
        webhookAuthMethodsUpdatedHandler
      );
    }

    devtools.connect();

    void requestSessionContext();

    return () => {
      devtools.disconnect();
      if (channel) {
        channel.off('session_context', sessionContextHandler);
        channel.off('session_context_updated', sessionContextUpdatedHandler);
        channel.off('workflow_saved', workflowSavedHandler);
        channel.off(
          'webhook_auth_methods_updated',
          webhookAuthMethodsUpdatedHandler
        );
      }
      _channelProvider = null;
    };
  };

  /**
   * Request session context from server via channel
   */
  const requestSessionContext = async (): Promise<void> => {
    if (!_channelProvider?.channel) {
      logger.warn('Cannot request session context - no channel connected');
      setError('No connection available');
      return;
    }

    setLoading(true);
    clearError();

    try {
      logger.debug('Requesting session context');
      // Note: Elixir handler returns {user, project, config} directly
      // NOT wrapped in session_context key
      // See lib/lightning_web/channels/workflow_channel.ex line 96-102
      const response = await channelRequest(
        _channelProvider.channel,
        'get_context',
        {}
      );

      handleSessionContextReceived(response);
    } catch (error) {
      logger.error('Session context request failed', error);
      setError('Failed to request session context');
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

    // Commands (CQS pattern)
    requestSessionContext,
    setLoading,
    setError,
    clearError,
    setLatestSnapshotLockVersion,
    clearIsNewWorkflow,

    // Internal methods (not part of public SessionContextStore interface)
    _connectChannel,
  };
};

export type SessionContextStoreInstance = ReturnType<
  typeof createSessionContextStore
>;
