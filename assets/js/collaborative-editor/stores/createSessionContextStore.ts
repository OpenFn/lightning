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
  VersionSchema,
  WebhookAuthMethodSchema,
  WorkflowTemplateSchema,
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
      versions: [],
      versionsLoading: false,
      versionsError: null,
      workflow_template: null,
      hasReadAIDisclaimer: false,
      limits: {},
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
    console.log('han:base', result.data?.workflow, result.error, rawData);

    if (result.success) {
      const sessionContext = result.data;

      state = produce(state, draft => {
        draft.user = sessionContext.user;
        draft.project = sessionContext.project;
        draft.workflow = sessionContext.workflow ?? null;
        draft.config = sessionContext.config;
        draft.permissions = sessionContext.permissions;
        draft.latestSnapshotLockVersion =
          sessionContext.latest_snapshot_lock_version;
        draft.projectRepoConnection = sessionContext.project_repo_connection;
        draft.webhookAuthMethods = sessionContext.webhook_auth_methods;
        draft.workflow_template = sessionContext.workflow_template;
        draft.hasReadAIDisclaimer = sessionContext.has_read_ai_disclaimer;
        draft.limits = sessionContext.limits;
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
   * Clears versions cache when lock version changes (not on initial set)
   */
  const setLatestSnapshotLockVersion = (lockVersion: number) => {
    state = produce(state, draft => {
      const previousLockVersion = draft.latestSnapshotLockVersion;

      // Clear versions if lock version changed (not on initial set)
      if (previousLockVersion !== null && previousLockVersion !== lockVersion) {
        draft.versions = [];
      }

      draft.latestSnapshotLockVersion = lockVersion;
      draft.lastUpdated = Date.now();
    });
    notify('setLatestSnapshotLockVersion');
  };

  const setBaseWorkflow = (workflow: unknown) => {
    state = produce(state, draft => {
      draft.workflow = workflow as any;
    });
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

  /**
   * Set AI disclaimer read status (local state only)
   * Called when user accepts the AI assistant disclaimer
   */
  const setHasReadAIDisclaimer = (hasRead: boolean) => {
    state = produce(state, draft => {
      draft.hasReadAIDisclaimer = hasRead;
    });
    notify('setHasReadAIDisclaimer');
  };

  /**
   * Mark AI disclaimer as read and persist to backend
   * Called when user accepts the AI assistant disclaimer
   */
  const markAIDisclaimerRead = async (): Promise<void> => {
    if (!_channelProvider?.channel) {
      logger.warn('Cannot mark disclaimer read - no channel connected');
      return;
    }

    try {
      await channelRequest(
        _channelProvider.channel,
        'mark_ai_disclaimer_read',
        {}
      );
      setHasReadAIDisclaimer(true);
    } catch (error) {
      logger.error('Failed to mark disclaimer read', error);
    }
  };

  /**
   * Request workflow versions from server via channel
   */
  const requestVersions = async (): Promise<void> => {
    // Early return if already loading or no channel
    if (state.versionsLoading || !_channelProvider?.channel) {
      if (!_channelProvider?.channel) {
        logger.warn('Cannot request versions - no channel connected');
      }
      return;
    }

    state = produce(state, draft => {
      draft.versionsLoading = true;
      draft.versionsError = null;
    });
    notify('requestVersions:start');

    try {
      logger.debug('Requesting workflow versions');
      const response = await channelRequest<{ versions: unknown[] }>(
        _channelProvider.channel,
        'request_versions',
        {}
      );

      // Validate versions array with Zod
      const result = z.array(VersionSchema).safeParse(response.versions);

      if (result.success) {
        state = produce(state, draft => {
          draft.versions = result.data;
          draft.versionsLoading = false;
          draft.versionsError = null;
        });
        notify('requestVersions:success');
      } else {
        const errorMessage = `Invalid versions data: ${result.error.message}`;
        logger.error('Failed to parse versions data', {
          error: result.error,
          response,
        });

        state = produce(state, draft => {
          draft.versionsError = errorMessage;
          draft.versionsLoading = false;
        });
        notify('requestVersions:error');
      }
    } catch (error) {
      logger.error('Versions request failed', error);
      state = produce(state, draft => {
        draft.versionsError = 'Failed to load versions';
        draft.versionsLoading = false;
      });
      notify('requestVersions:error');
    }
  };

  /**
   * Clear versions cache
   */
  const clearVersions = () => {
    state = produce(state, draft => {
      draft.versions = [];
    });
    notify('clearVersions');
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
        if ('workflow' in message) {
          setBaseWorkflow(message.workflow);
        }
      }
    };

    const webhookAuthMethodsUpdatedHandler = (message: unknown) => {
      logger.debug('Received webhook_auth_methods_updated message', message);
      handleWebhookAuthMethodsUpdated(message);
    };

    const templateUpdatedHandler = (message: unknown) => {
      logger.debug('Received template_updated message', message);

      const result = z
        .object({
          workflow_template: WorkflowTemplateSchema.nullable(),
        })
        .safeParse(message);

      if (result.success) {
        state = produce(state, draft => {
          draft.workflow_template = result.data.workflow_template;
          draft.lastUpdated = Date.now();
        });
        notify('templateUpdated');
      } else {
        logger.error('Failed to parse template_updated message', {
          error: result.error,
          message,
        });
      }
    };

    const getLimitsHandler = (message: unknown) => {
      logger.debug('Received get_limits message', message);

      // Validate get_limits response
      const result = z
        .object({
          action_type: z.string(),
          limit: z.object({
            allowed: z.boolean(),
            message: z.string().nullable(),
          }),
        })
        .safeParse(message);

      if (result.success) {
        const { action_type, limit } = result.data;

        // Update the specific limit type
        if (action_type === 'new_run') {
          state = produce(state, draft => {
            draft.limits.runs = limit;
            draft.lastUpdated = Date.now();
          });
          notify('getLimits');
        } else if (action_type === 'activate_workflow') {
          state = produce(state, draft => {
            draft.limits.workflow_activation = limit;
            draft.lastUpdated = Date.now();
          });
          notify('getLimits');
        } else if (action_type === 'github_sync') {
          state = produce(state, draft => {
            draft.limits.github_sync = limit;
            draft.lastUpdated = Date.now();
          });
          notify('getLimits');
        }
      } else {
        logger.error('Failed to parse get_limits message', {
          error: result.error,
          message,
        });
      }
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
      channel.on('template_updated', templateUpdatedHandler);
      channel.on('get_limits', getLimitsHandler);
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
        channel.off('template_updated', templateUpdatedHandler);
        channel.off('get_limits', getLimitsHandler);
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

  /**
   * Get limits for a specific action type
   * Sends request to server and updates limits state via channel handler
   */
  const getLimits = async (
    actionType: 'new_run' | 'activate_workflow' | 'github_sync'
  ): Promise<void> => {
    if (!_channelProvider?.channel) {
      logger.warn('Cannot get limits - no channel connected');
      return;
    }

    try {
      logger.debug('Getting limits for action', actionType);
      await _channelProvider.channel.push('get_limits', {
        action_type: actionType,
      });
    } catch (error) {
      logger.error('Failed to get limits', error);
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
    requestVersions,
    clearVersions,
    setLoading,
    setError,
    clearError,
    setLatestSnapshotLockVersion,
    clearIsNewWorkflow,
    setHasReadAIDisclaimer,
    markAIDisclaimerRead,
    getLimits,

    // Internal methods (not part of public SessionContextStore interface)
    _connectChannel,
  };
};

export type SessionContextStoreInstance = ReturnType<
  typeof createSessionContextStore
>;
