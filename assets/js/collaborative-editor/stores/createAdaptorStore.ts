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
  type Adaptor,
  type AdaptorState,
  type AdaptorStore,
  AdaptorsListSchema,
} from "../types/adaptor";

/**
 * Creates an adaptor store instance with useSyncExternalStore + Immer pattern
 */
export const createAdaptorStore = (): AdaptorStore => {
  // Single Immer-managed state object (referentially stable)
  let state: AdaptorState = produce(
    {
      adaptors: [],
      isLoading: false,
      error: null,
      lastUpdated: null,
    } as AdaptorState,
    // No initial transformations needed
    (draft) => draft,
  );

  const listeners = new Set<() => void>();

  const notify = () => {
    listeners.forEach((listener) => listener());
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
  const withSelector = <T>(selector: (state: AdaptorState) => T) => {
    let lastResult: T;
    let lastState: AdaptorState | undefined;

    return (): T => {
      const currentState = getSnapshot();

      // Only recompute if state reference actually changed
      if (currentState !== lastState) {
        const newResult = selector(currentState);

        // Always update result when state changes (Immer guarantees stable references)
        lastResult = newResult;
        lastState = currentState;
      }

      return lastResult;
    };
  };

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
      state = produce(state, (draft) => {
        draft.adaptors = result.data;
        draft.isLoading = false;
        draft.error = null;
        draft.lastUpdated = Date.now();
      });
      notify();
    } else {
      const errorMessage = `Invalid adaptors data: ${result.error.message}`;
      console.error("AdaptorStore: Failed to parse adaptors data", {
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

  const setAdaptors = (adaptors: Adaptor[]) => {
    state = produce(state, (draft) => {
      draft.adaptors = adaptors;
      draft.lastUpdated = Date.now();
      draft.error = null;
    });
    notify();
  };

  // =============================================================================
  // CHANNEL INTEGRATION
  // =============================================================================

  let channelProvider: PhoenixChannelProvider | null = null;

  /**
   * Connect to Phoenix channel provider for real-time updates
   */
  const connectChannel = (provider: unknown) => {
    const typedProvider = provider as PhoenixChannelProvider;
    channelProvider = typedProvider;

    // Listen for adaptor-related channel messages
    const adaptorsListHandler = (message: unknown) => {
      console.debug("AdaptorStore: Received adaptors_list message", message);
      handleAdaptorsReceived(message);
    };

    const adaptorsUpdatedHandler = (message: unknown) => {
      console.debug("AdaptorStore: Received adaptors_updated message", message);
      handleAdaptorsUpdated(message);
    };

    // Set up channel listeners
    if (typedProvider.channel) {
      typedProvider.channel.on("adaptors_list", adaptorsListHandler);
      typedProvider.channel.on("adaptors_updated", adaptorsUpdatedHandler);
    }

    return () => {
      if (typedProvider.channel) {
        typedProvider.channel.off("adaptors_list", adaptorsListHandler);
        typedProvider.channel.off("adaptors_updated", adaptorsUpdatedHandler);
      }
      channelProvider = null;
    };
  };

  /**
   * Request adaptors from server via channel
   */
  const requestAdaptors = () => {
    if (!channelProvider?.channel) {
      console.warn(
        "AdaptorStore: Cannot request adaptors - no channel connected",
      );
      setError("No connection available");
      return;
    }

    setLoading(true);
    clearError();

    // Send request to Phoenix channel
    channelProvider.channel
      .push("request_adaptors", {})
      .receive("ok", (response: unknown) => {
        console.debug("AdaptorStore: Adaptor request acknowledged", response);
        // If response contains adaptors data directly, handle it
        if (
          response &&
          typeof response === "object" &&
          "adaptors" in response
        ) {
          handleAdaptorsReceived((response as { adaptors: unknown }).adaptors);
        }
        // Otherwise, response will come through separate channel message
      })
      .receive("error", (error: unknown) => {
        console.error("AdaptorStore: Adaptor request failed", error);
        const errorMessage =
          error && typeof error === "object" && "reason" in error
            ? (error as { reason: string }).reason
            : "Unknown error";
        setError(`Failed to request adaptors: ${errorMessage}`);
      })
      .receive("timeout", () => {
        console.error("AdaptorStore: Adaptor request timed out");
        setError("Request timed out");
      });
  };

  // =============================================================================
  // QUERY HELPERS
  // =============================================================================

  const findAdaptorByName = (name: string): Adaptor | null => {
    return state.adaptors.find((adaptor) => adaptor.name === name) || null;
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
    setAdaptors,
    setLoading,
    setError,
    clearError,

    // Queries (CQS pattern)
    findAdaptorByName,
    getLatestVersion,
    getVersions,

    // Internal methods (not part of public AdaptorStore interface)
    _internal: {
      connectChannel,
      handleAdaptorsReceived,
      handleAdaptorsUpdated,
    },
  };
};

export type AdaptorStoreInstance = ReturnType<typeof createAdaptorStore>;
