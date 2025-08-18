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

import { produce } from "immer";
import type { PhoenixChannelProvider } from "y-phoenix-channel";

import {
  type CredentialState,
  type CredentialStore,
  CredentialsListSchema,
} from "../types/credential";

import { createWithSelector } from "./common";

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
    (draft) => draft,
  );

  const listeners = new Set<() => void>();

  const notify = () => {
    listeners.forEach((listener) => {
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
  // PATTERN 1: Channel Message → Immer → Notify (Server Updates)
  // =============================================================================

  /**
   * Handle credentials list received from server
   * Validates data with Zod before updating state
   */
  const _handleCredentialsReceived = (rawData: unknown) => {
    const result = CredentialsListSchema.safeParse(rawData);

    if (result.success) {
      const credentials = result.data;

      credentials.project_credentials.sort((a, b) =>
        a.name.localeCompare(b.name),
      );
      credentials.keychain_credentials.sort((a, b) =>
        a.name.localeCompare(b.name),
      );

      state = produce(state, (draft) => {
        draft.projectCredentials = credentials.project_credentials;
        draft.keychainCredentials = credentials.keychain_credentials;
        draft.isLoading = false;
        draft.error = null;
        draft.lastUpdated = Date.now();
      });
      notify();
    } else {
      const errorMessage = `Invalid credentials data: ${result.error.message}`;
      console.error("CredentialStore: Failed to parse credentials data", {
        error: result.error,
        rawData,
      });

      state = produce(state, (draft) => {
        draft.isLoading = false;
        draft.error = errorMessage;
      });
      notify();
    }
  };

  /**
   * Handle real-time credentials update from server
   */
  const _handleCredentialsUpdated = (rawData: unknown) => {
    // Same validation logic as handleCredentialsReceived
    _handleCredentialsReceived(rawData);
  };

  // =============================================================================
  // PATTERN 2: Direct Immer → Notify (Local State)
  // =============================================================================

  const setLoading = (loading: boolean) => {
    state = produce(state, (draft) => {
      draft.isLoading = loading;
    });
    notify();
  };

  const setError = (error: string | null) => {
    state = produce(state, (draft) => {
      draft.error = error;
      draft.isLoading = false;
    });
    notify();
  };

  const clearError = () => {
    state = produce(state, (draft) => {
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

    // Listen for credential-related channel messages
    const credentialsListHandler = (message: unknown) => {
      console.debug(
        "CredentialStore: Received credentials_list message",
        message,
      );
      _handleCredentialsReceived(message);
    };

    const credentialsUpdatedHandler = (message: unknown) => {
      console.debug(
        "CredentialStore: Received credentials_updated message",
        message,
      );
      _handleCredentialsUpdated(message);
    };

    // Set up channel listeners
    if (channel) {
      channel.on("credentials_list", credentialsListHandler);
      channel.on("credentials_updated", credentialsUpdatedHandler);
    }

    requestCredentials();

    return () => {
      if (channel) {
        channel.off("credentials_list", credentialsListHandler);
        channel.off("credentials_updated", credentialsUpdatedHandler);
      }
      _channelProvider = null;
    };
  };

  /**
   * Request credentials from server via channel
   */
  const requestCredentials = () => {
    if (!_channelProvider?.channel) {
      console.warn(
        "CredentialStore: Cannot request credentials - no channel connected",
      );
      setError("No connection available");
      return;
    }

    setLoading(true);
    clearError();

    // Send request to Phoenix channel
    _channelProvider.channel
      .push("request_credentials", {})
      .receive("ok", (response: unknown) => {
        console.debug(
          "CredentialStore: Credential request acknowledged",
          response,
        );
        // If response contains credentials data directly, handle it
        if (
          response &&
          typeof response === "object" &&
          "credentials" in response
        ) {
          _handleCredentialsReceived(
            (response as { credentials: unknown }).credentials,
          );
        }
        // Otherwise, response will come through separate channel message
      })
      .receive("error", (error: unknown) => {
        console.error("CredentialStore: Credential request failed", error);
        const errorMessage =
          error && typeof error === "object" && "reason" in error
            ? (error as { reason: string }).reason
            : "Unknown error";
        setError(`Failed to request credentials: ${errorMessage}`);
      })
      .receive("timeout", () => {
        console.error("CredentialStore: Credential request timed out");
        setError("Request timed out");
      });
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
    requestCredentials,
    setLoading,
    setError,
    clearError,

    // Internal methods (not part of public CredentialStore interface)
    _connectChannel,
    _handleCredentialsReceived,
    _handleCredentialsUpdated,
  };
};

export type CredentialStoreInstance = ReturnType<typeof createCredentialStore>;
