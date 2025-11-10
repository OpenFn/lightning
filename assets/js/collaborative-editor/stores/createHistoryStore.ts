/**
 * # HistoryStore - Workflow Execution History Management
 *
 * Manages workflow execution history and detailed run step data with intelligent
 * caching and real-time synchronization.
 *
 * ## Data Held
 *
 * - **history**: Array of work orders (top 20 most recent), each containing runs
 * - **runStepsCache**: Cached detailed step data keyed by run ID
 * - **runStepsSubscribers**: Tracks which components are watching each run
 * - **runStepsLoading**: In-flight run step requests to prevent duplicates
 * - **isLoading/error**: Request states for user feedback
 * - **isChannelConnected**: Phoenix channel connection status
 * - **lastUpdated**: Timestamp of last successful history update
 *
 * ## Channel Interactions
 *
 * **Listens to:**
 * - `history_updated` - Real-time work order and run updates from server
 *   - Handles: work_order created/updated, run created/updated
 *   - Automatically invalidates and refetches affected run steps
 *
 * **Makes requests:**
 * - `request_history` - Fetches top 20 work orders (optionally filtered to include specific run)
 * - `request_run_steps` - Fetches detailed step execution data for a run
 *
 * ## Hook Interface
 *
 * **State Queries:**
 * - `useHistory()` - Returns work order array
 * - `useHistoryLoading()` - Returns loading state
 * - `useHistoryError()` - Returns error message
 * - `useHistoryChannelConnected()` - Returns channel status
 *
 * **Commands (via useHistoryCommands):**
 * - `requestHistory(runId?)` - Fetch history from server
 * - `requestRunSteps(runId)` - Fetch run steps from server
 * - `getRunSteps(runId)` - Read cached run steps (no fetch)
 * - `clearError()` - Clear error state
 *
 * **Advanced Subscription Hook:**
 * - `useRunSteps(runId)` - Subscribe to run steps with automatic lifecycle management
 *   - Auto-subscribes on mount, unsubscribes on unmount
 *   - Auto-fetches if not cached
 *   - Auto-refetches when run updates (if subscribed)
 *   - Auto-cleans cache when last subscriber unmounts
 *   - Returns transformed RunInfo for visualization
 *
 * ## Key Behaviors
 *
 * ### Subscription-Based Caching
 * Components declare interest via subscribeToRunSteps(runId, componentId).
 * Store tracks subscribers per run and only caches actively watched runs.
 * Multiple components can subscribe to the same run.
 *
 * ### Selective Cache Invalidation
 * When history_updated event arrives with run changes:
 * - Check if run has active subscribers
 * - If yes: invalidate cache and trigger refetch
 * - If no: ignore (no components need fresh data)
 *
 * ### Automatic Memory Cleanup
 * When last subscriber unsubscribes from a run:
 * - Remove cached run steps
 * - Remove subscriber tracking
 * - Clear loading state
 * Prevents memory leaks in long-lived sessions.
 *
 * ### Request Deduplication
 * Tracks in-flight requests in runStepsLoading Set to prevent
 * duplicate concurrent fetches for the same run.
 *
 * ## Redux DevTools Integration
 *
 * Install Redux DevTools extension and select "HistoryStore" to inspect:
 * - Current state (history, cache, subscribers)
 * - Action history with timestamps
 * - Time-travel debugging
 * - State export/import for bug reproduction
 */

import { produce } from 'immer';
import type { PhoenixChannelProvider } from 'y-phoenix-channel';

import _logger from '#/utils/logger';

import { channelRequest } from '../hooks/useChannel';
import {
  type HistoryState,
  type HistoryStore,
  HistoryListSchema,
  type WorkOrder,
  type Run,
  type RunStepsData,
} from '../types/history';

import { createWithSelector } from './common';
import { wrapStoreWithDevTools } from './devtools';

const logger = _logger.ns('HistoryStore').seal();

/**
 * Creates a history store instance with useSyncExternalStore +
 * Immer pattern
 */
export const createHistoryStore = (): HistoryStore => {
  // Single Immer-managed state object (referentially stable)
  let state: HistoryState = produce(
    {
      history: [],
      isLoading: false,
      error: null,
      lastUpdated: null,
      isChannelConnected: false,
      runStepsCache: {},
      runStepsSubscribers: {},
      runStepsLoading: new Set(),
    } as HistoryState,
    // No initial transformations needed
    draft => draft
  );

  const listeners = new Set<() => void>();

  // Redux DevTools integration
  const devtools = wrapStoreWithDevTools({
    name: 'HistoryStore',
    excludeKeys: [], // All state is serializable
    maxAge: 100,
  });

  const notify = (actionName: string = 'stateChange') => {
    devtools.notifyWithAction(actionName, () => state);
    listeners.forEach(listener => {
      listener();
    });
  };

  // ===========================================================================
  // CORE STORE INTERFACE
  // ===========================================================================

  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  const getSnapshot = (): HistoryState => state;

  // withSelector utility - creates memoized selectors for referential
  // stability
  const withSelector = createWithSelector(getSnapshot);

  // ===========================================================================
  // PATTERN 1: Channel Message → Zod → Immer → Notify (Server Updates)
  // ===========================================================================

  /**
   * Handle history list received from server
   * Validates data with Zod before updating state
   */
  const handleHistoryReceived = (rawData: unknown) => {
    const result = HistoryListSchema.safeParse(rawData);

    if (result.success) {
      state = produce(state, draft => {
        draft.history = result.data;
        draft.isLoading = false;
        draft.error = null;
        draft.lastUpdated = Date.now();
      });
      notify('handleHistoryReceived');
    } else {
      const errorMessage = `Invalid history data: ${result.error.message}`;
      logger.error('Failed to parse history data', {
        error: result.error,
        rawData,
      });

      state = produce(state, draft => {
        draft.isLoading = false;
        draft.error = errorMessage;
      });
      notify('historyError');
    }
  };

  /**
   * Handle real-time history updates from server
   * Supports multiple action types: created, updated, run_created,
   * run_updated
   */
  const handleHistoryUpdated = (payload: {
    action: 'created' | 'updated' | 'run_created' | 'run_updated';
    work_order?: WorkOrder;
    run?: Run;
    work_order_id?: string;
  }) => {
    const { action, work_order, run, work_order_id } = payload;

    state = produce(state, draft => {
      // Handle work order created/updated
      if ((action === 'created' || action === 'updated') && work_order) {
        const existingIndex = draft.history.findIndex(
          wo => wo.id === work_order.id
        );

        if (existingIndex !== -1) {
          // Update existing work order
          draft.history[existingIndex] = work_order;
        } else {
          // Add new work order (can happen if we missed "created" event)
          draft.history.unshift(work_order);
          // Keep only top 20
          if (draft.history.length > 20) draft.history.pop();
        }
      }

      // Handle run created/updated
      if (
        (action === 'run_created' || action === 'run_updated') &&
        run &&
        work_order_id
      ) {
        const wo = draft.history.find(wo => wo.id === work_order_id);
        if (!wo) {
          logger.warn('Work order not found in history', {
            workOrderId: work_order_id,
            existingWorkOrderIds: draft.history.map(wo => wo.id),
          });
          return;
        }

        const existingRunIndex = wo.runs.findIndex(r => r.id === run.id);
        if (existingRunIndex !== -1) {
          // Update existing run
          wo.runs[existingRunIndex] = run;
        } else if (action === 'run_created') {
          // Add new run (only for "created" action)
          wo.runs.unshift(run);
        } else {
          // run_updated but run doesn't exist - unusual but log it
          logger.warn('Run not found in work order runs array', {
            runId: run.id,
            workOrderId: work_order_id,
            existingRunIds: wo.runs.map(r => r.id),
          });
        }
      }

      // Invalidate cached run steps if someone is watching this run
      if ((action === 'run_updated' || action === 'run_created') && run) {
        const subscribersForThisRun = draft.runStepsSubscribers[run.id];
        if (subscribersForThisRun && subscribersForThisRun.size > 0) {
          // Invalidate cache - next read will trigger refetch
          Reflect.deleteProperty(draft.runStepsCache, run.id);
        }
      }

      draft.lastUpdated = Date.now();
    });
    notify('handleHistoryUpdated');

    // Trigger refetch for invalidated runs with subscribers
    if ((action === 'run_updated' || action === 'run_created') && run) {
      const currentState = getSnapshot();
      const subscribers = currentState.runStepsSubscribers[run.id];
      if (subscribers && subscribers.size > 0) {
        // Asynchronously refetch - don't await
        void requestRunSteps(run.id);
      }
    }
  };

  // ===========================================================================
  // PATTERN 2: Direct Immer → Notify (Local State)
  // ===========================================================================

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

  // ===========================================================================
  // CHANNEL INTEGRATION
  // ===========================================================================

  let _channelProvider: PhoenixChannelProvider | null = null;

  /**
   * Connect to Phoenix channel provider for real-time updates
   */
  const _connectChannel = (channelProvider: PhoenixChannelProvider) => {
    _channelProvider = channelProvider;
    const channel = channelProvider.channel;

    // Update connection state
    state = produce(state, draft => {
      draft.isChannelConnected = true;
    });
    notify('channelConnected');

    // Listen for history-related channel messages
    const historyUpdatedHandler = (message: unknown) => {
      const payload = message as {
        action: 'created' | 'updated' | 'run_created' | 'run_updated';
        work_order?: WorkOrder;
        run?: Run;
        work_order_id?: string;
      };
      handleHistoryUpdated(payload);
    };

    // Set up channel listeners
    if (channel) {
      channel.on('history_updated', historyUpdatedHandler);

      devtools.connect();

      return () => {
        devtools.disconnect();
        channel.off('history_updated', historyUpdatedHandler);
        _channelProvider = null;

        // Update connection state
        state = produce(state, draft => {
          draft.isChannelConnected = false;
        });
        notify('channelDisconnected');
      };
    } else {
      logger.warn('No channel available to set up listeners');
      devtools.connect();

      return () => {
        devtools.disconnect();
        _channelProvider = null;

        // Update connection state
        state = produce(state, draft => {
          draft.isChannelConnected = false;
        });
        notify('channelDisconnected');
      };
    }
  };

  /**
   * Request history from server via channel
   * Optionally includes a specific run_id to ensure that run's work order
   * is included even if it's older than the top 20
   */
  const requestHistory = async (runId?: string): Promise<void> => {
    if (!_channelProvider?.channel) {
      logger.warn('Cannot request history - no channel connected');
      setError('No connection available');
      return;
    }

    setLoading(true);
    clearError();

    try {
      const response = await channelRequest<{ history: unknown }>(
        _channelProvider.channel,
        'request_history',
        runId ? { run_id: runId } : {}
      );

      if (response.history) {
        handleHistoryReceived(response.history);
      } else {
        // Still need to set loading to false
        setLoading(false);
      }
    } catch (error) {
      logger.error('History request failed', error);
      setError('Failed to request history');
    }
  };

  /**
   * Request run steps from server via channel
   * Returns step data for a specific run, or null if request fails
   */
  const requestRunSteps = async (
    runId: string
  ): Promise<RunStepsData | null> => {
    if (!_channelProvider?.channel) {
      logger.warn('Cannot request run steps - no channel connected');
      return null;
    }

    state = produce(state, draft => {
      draft.isLoading = true;
      draft.error = null;
      draft.runStepsLoading.add(runId);
    });
    notify('requestRunSteps/start');

    try {
      const response = await channelRequest<RunStepsData>(
        _channelProvider.channel,
        'request_run_steps',
        { run_id: runId }
      );

      state = produce(state, draft => {
        draft.runStepsCache[runId] = response;
        draft.isLoading = false;
        draft.runStepsLoading.delete(runId);
      });
      notify('requestRunSteps/success');

      return response;
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : 'Failed to fetch run steps';

      logger.error('Run steps request failed', { error, runId });

      state = produce(state, draft => {
        draft.error = errorMessage;
        draft.isLoading = false;
        draft.runStepsLoading.delete(runId);
      });
      notify('requestRunSteps/error');

      return null;
    }
  };

  // ===========================================================================
  // QUERIES (CQS Pattern)
  // ===========================================================================

  /**
   * Get cached run steps for a specific run
   * Returns null if not in cache
   */
  const getRunSteps = (runId: string): RunStepsData | null => {
    const currentState = getSnapshot();
    return currentState.runStepsCache[runId] || null;
  };

  // ===========================================================================
  // SUBSCRIPTION MANAGEMENT
  // ===========================================================================

  /**
   * Subscribe a component to run steps for a specific run ID.
   *
   * Pattern: Component calls this on mount via useEffect.
   * Automatically fetches run steps if not cached and not already loading.
   * Multiple components can subscribe to the same run ID.
   *
   * @param runId - The run ID to subscribe to
   * @param subscriberId - Unique ID for the subscribing component
   */
  const subscribeToRunSteps = (runId: string, subscriberId: string): void => {
    state = produce(state, draft => {
      // Initialize subscriber set if first subscription for this run
      if (!draft.runStepsSubscribers[runId]) {
        draft.runStepsSubscribers[runId] = new Set();
      }

      // Add this component to subscribers
      draft.runStepsSubscribers[runId].add(subscriberId);
    });
    notify('subscribeToRunSteps');

    // Fetch if we don't have cached data and aren't already loading
    const currentState = getSnapshot();
    const needsFetch =
      !currentState.runStepsCache[runId] &&
      !currentState.runStepsLoading.has(runId);

    if (needsFetch) {
      void requestRunSteps(runId);
    }
  };

  /**
   * Unsubscribe a component from run steps for a specific run ID.
   *
   * Pattern: Component calls this on unmount via useEffect cleanup.
   * Automatically cleans up cache when last subscriber unsubscribes.
   *
   * @param runId - The run ID to unsubscribe from
   * @param subscriberId - Unique ID of the unsubscribing component
   */
  const unsubscribeFromRunSteps = (
    runId: string,
    subscriberId: string
  ): void => {
    state = produce(state, draft => {
      const subscribers = draft.runStepsSubscribers[runId];
      if (!subscribers) {
        logger.warn('Attempted to unsubscribe from non-existent subscription', {
          runId,
          subscriberId,
        });
        return;
      }

      // Remove this component from subscribers
      subscribers.delete(subscriberId);

      // Clean up if no more subscribers
      if (subscribers.size === 0) {
        // Use Reflect.deleteProperty for dynamically computed keys
        Reflect.deleteProperty(draft.runStepsCache, runId);
        Reflect.deleteProperty(draft.runStepsSubscribers, runId);
        draft.runStepsLoading.delete(runId);
      }
    });
    notify('unsubscribeFromRunSteps');
  };

  // ===========================================================================
  // PUBLIC INTERFACE
  // ===========================================================================

  return {
    // Core store interface
    subscribe,
    getSnapshot,
    withSelector,

    // Queries (CQS pattern)
    getRunSteps,

    // Commands (CQS pattern)
    requestHistory,
    requestRunSteps,
    setLoading,
    setError,
    clearError,
    subscribeToRunSteps,
    unsubscribeFromRunSteps,

    // Internal methods (not part of public HistoryStore interface)
    _connectChannel,
  };
};

export type HistoryStoreInstance = ReturnType<typeof createHistoryStore>;
