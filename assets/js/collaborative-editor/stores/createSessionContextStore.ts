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

import { produce } from "immer";
import type { PhoenixChannelProvider } from "y-phoenix-channel";

import _logger from "#/utils/logger";

import { channelRequest } from "../hooks/useChannel";
import {
  type SessionContextState,
  type SessionContextStore,
  SessionContextResponseSchema,
} from "../types/sessionContext";

import { createWithSelector } from "./common";

const logger = _logger.ns("SessionContextStore").seal();

/**
 * Creates a session context store instance with useSyncExternalStore + Immer pattern
 */
export const createSessionContextStore = (): SessionContextStore => {
  // Single Immer-managed state object (referentially stable)
  let state: SessionContextState = produce(
    {
      user: null,
      project: null,
      config: null,
      isLoading: false,
      error: null,
      lastUpdated: null,
    } as SessionContextState,
    // No initial transformations needed
    draft => draft
  );

  const listeners = new Set<() => void>();

  const notify = () => {
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
        draft.isLoading = false;
        draft.error = null;
        draft.lastUpdated = Date.now();
      });
      notify();
    } else {
      const errorMessage = `Invalid session context data: ${result.error.message}`;
      logger.error("Failed to parse session context data", {
        error: result.error,
        rawData,
      });

      state = produce(state, draft => {
        draft.isLoading = false;
        draft.error = errorMessage;
      });
      notify();
    }
  };

  /**
   * Handle real-time session context update from server
   */
  const handleSessionContextUpdated = (rawData: unknown) => {
    // Same validation logic as handleSessionContextReceived
    handleSessionContextReceived(rawData);
  };

  // =============================================================================
  // PATTERN 2: Direct Immer → Notify (Local State)
  // =============================================================================

  const setLoading = (loading: boolean) => {
    state = produce(state, draft => {
      draft.isLoading = loading;
    });
    notify();
  };

  const setError = (error: string | null) => {
    state = produce(state, draft => {
      draft.error = error;
      draft.isLoading = false;
    });
    notify();
  };

  const clearError = () => {
    state = produce(state, draft => {
      draft.error = null;
    });
    notify();
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
      logger.debug("Received session_context message", message);
      handleSessionContextReceived(message);
    };

    const sessionContextUpdatedHandler = (message: unknown) => {
      logger.debug("Received session_context_updated message", message);
      handleSessionContextUpdated(message);
    };

    // Set up channel listeners
    if (channel) {
      channel.on("session_context", sessionContextHandler);
      channel.on("session_context_updated", sessionContextUpdatedHandler);
    }

    void requestSessionContext();

    return () => {
      if (channel) {
        channel.off("session_context", sessionContextHandler);
        channel.off("session_context_updated", sessionContextUpdatedHandler);
      }
      _channelProvider = null;
    };
  };

  /**
   * Request session context from server via channel
   */
  const requestSessionContext = async (): Promise<void> => {
    if (!_channelProvider?.channel) {
      logger.warn("Cannot request session context - no channel connected");
      setError("No connection available");
      return;
    }

    setLoading(true);
    clearError();

    try {
      logger.debug("Requesting session context");
      const response = await channelRequest<{
        session_context: unknown;
      }>(_channelProvider.channel, "get_context", {});

      if (response.session_context) {
        handleSessionContextReceived(response.session_context);
      }
    } catch (error) {
      logger.error("Session context request failed", error);
      setError("Failed to request session context");
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

    // Internal methods (not part of public SessionContextStore interface)
    _connectChannel,
  };
};

export type SessionContextStoreInstance = ReturnType<
  typeof createSessionContextStore
>;
