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
 * Store tracks subscribers per run. Multiple components can subscribe to the same run.
 *
 * ### Server-Side Cache Pre-population
 * On page load with a run selected (URL has `?run=xxx`), the server provides
 * initial run data via data attributes. This is passed to createHistoryStore()
 * to pre-populate the cache, enabling instant rendering without loading flash.
 *
 * ### Selective Cache Invalidation
 * When history_updated event arrives with run changes:
 * - Check if run has active subscribers
 * - If yes: invalidate cache and trigger refetch
 * - If no: ignore (no components need fresh data)
 *
 * ### Cache Persistence
 * Cache entries are NOT cleared when subscribers unsubscribe. This prevents
 * bugs with React StrictMode's double-mount cycle. Cache is small (~1KB per run)
 * and is cleaned up when the store is recreated on navigation.
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
import type { Channel } from 'phoenix';
import type { PhoenixChannelProvider } from 'y-phoenix-channel';

import _logger from '#/utils/logger';

import { channelRequest } from '../hooks/useChannel';
import {
  type HistoryState,
  type HistoryStore,
  type RunDetail,
  type RunStepsData,
  type RunSummary,
  type StepDetail,
  type WorkOrder,
  HistoryListSchema,
  RunDetailSchema,
  StepDetailSchema,
} from '../types/history';

import { createWithSelector } from './common';
import { wrapStoreWithDevTools } from './devtools';

const logger = _logger.ns('HistoryStore').seal();

/**
 * Options for creating a history store
 */
interface CreateHistoryStoreOptions {
  /**
   * Initial run data from server to pre-populate cache.
   *
   * This eliminates race conditions on page reload by making run data available
   * BEFORE React mounts, rather than fetching after channel connection.
   *
   * Server-provided data is protected from cache cleanup during React StrictMode's
   * double-mount cycle (mount → unmount → remount), which would otherwise clear
   * the cache between mounts.
   */
  initialRunData?: RunStepsData | null;
}

/**
 * Creates a history store instance with useSyncExternalStore +
 * Immer pattern
 *
 * @param options - Optional configuration including initial run data from server
 */
export const createHistoryStore = (
  options?: CreateHistoryStoreOptions
): HistoryStore => {
  const initialRunData = options?.initialRunData;

  // Pre-populate cache with server-provided data for instant rendering on page load
  const initialCache: Record<string, RunStepsData> = {};
  if (initialRunData) {
    logger.log('Initializing cache with server-provided run data', {
      runId: initialRunData.run_id,
      stepCount: initialRunData.steps?.length,
    });
    initialCache[initialRunData.run_id] = initialRunData;
  }

  // Single Immer-managed state object (referentially stable)
  let state: HistoryState = produce(
    {
      // History browser state
      history: [],
      isLoading: false,
      error: null,
      lastUpdated: null,
      isChannelConnected: false,
      runStepsCache: initialCache,
      runStepsSubscribers: {},
      runStepsLoading: new Set(),

      // Active run viewer state
      activeRunId: null,
      activeRun: null,
      activeRunChannel: null,
      activeRunLoading: false,
      activeRunError: null,
      selectedStepId: null,
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
    run?: RunSummary;
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

  /**
   * Handle run data received from dedicated run channel
   * Full RunDetail with metadata for active viewing
   */
  const handleRunReceived = (rawData: unknown) => {
    const result = RunDetailSchema.safeParse(rawData);

    if (result.success) {
      state = produce(state, draft => {
        draft.activeRun = result.data;
        draft.activeRunLoading = false;
        draft.activeRunError = null;
        draft.lastUpdated = Date.now();

        // Auto-select first step if none selected
        if (!draft.selectedStepId && result.data.steps.length > 0) {
          draft.selectedStepId = result.data.steps[0]?.id || null;
        }
      });
      notify('handleRunReceived');
    } else {
      logger.error('Failed to parse run detail', result.error);
      state = produce(state, draft => {
        draft.activeRunLoading = false;
        draft.activeRunError = `Invalid run data: ${result.error.message}`;
      });
      notify('runError');
    }
  };

  /**
   * Handle run:updated event from dedicated run channel
   */
  const handleRunUpdated = (payload: { run: unknown }) => {
    const result = RunDetailSchema.safeParse(payload.run);

    if (result.success) {
      const updates = result.data;

      state = produce(state, draft => {
        if (draft.activeRun && draft.activeRun.id === updates.id) {
          // Merge updates while preserving steps array
          draft.activeRun = {
            ...draft.activeRun,
            ...updates,
          };
          draft.lastUpdated = Date.now();
        }
      });
      notify('handleRunUpdated');
    }
  };

  /**
   * Handle step:started event from dedicated run channel
   */
  const handleStepStarted = (payload: { step: unknown }) => {
    const result = StepDetailSchema.safeParse(payload.step);

    if (result.success) {
      handleStepUpdate(result.data);
    }
  };

  /**
   * Handle step:completed event from dedicated run channel
   */
  const handleStepCompleted = (payload: { step: unknown }) => {
    const result = StepDetailSchema.safeParse(payload.step);

    if (result.success) {
      handleStepUpdate(result.data);
    }
  };

  /**
   * Update step in active run AND cache (cache coordination)
   */
  const handleStepUpdate = (step: StepDetail) => {
    state = produce(state, draft => {
      // 1. Update active run
      if (draft.activeRun) {
        const activeIndex = draft.activeRun.steps.findIndex(
          s => s.id === step.id
        );
        if (activeIndex !== -1) {
          draft.activeRun.steps[activeIndex] = step;
        } else {
          // Add new step and sort by started_at
          draft.activeRun.steps.push(step);
          draft.activeRun.steps.sort((a, b) => {
            if (!a.started_at) return 1;
            if (!b.started_at) return -1;
            return (
              new Date(a.started_at).getTime() -
              new Date(b.started_at).getTime()
            );
          });
        }
      }

      // 2. Update cache if this run is cached (cache coordination)
      const runId = draft.activeRunId;
      if (runId) {
        const cacheEntry = draft.runStepsCache[runId];
        if (cacheEntry) {
          const cachedSteps = cacheEntry.steps;
          const cacheIndex = cachedSteps.findIndex(s => s.id === step.id);
          if (cacheIndex !== -1 && cachedSteps[cacheIndex]) {
            // Update shared fields (StepDetail and cached Step have
            // significant overlap)
            const cachedStep = cachedSteps[cacheIndex];
            cachedStep.started_at = step.started_at;
            cachedStep.finished_at = step.finished_at;
            cachedStep.exit_reason = step.exit_reason;
            cachedStep.error_type = step.error_type;
            // Only update input_dataclip_id if it's not null
            if (step.input_dataclip_id !== null) {
              cachedStep.input_dataclip_id = step.input_dataclip_id;
            }
            // Only update output_dataclip_id if it's not null
            if (step.output_dataclip_id !== null) {
              cachedStep.output_dataclip_id = step.output_dataclip_id;
            }
          } else {
            // Step not found in cache - add it (new step created during run)
            // This is the key fix: when step events arrive for newly created steps,
            // we add them to the cache so the canvas can display them in real-time
            cachedSteps.push({
              id: step.id,
              job_id: step.job_id,
              started_at: step.started_at,
              finished_at: step.finished_at,
              exit_reason: step.exit_reason,
              error_type: step.error_type,
              input_dataclip_id: step.input_dataclip_id,
              output_dataclip_id: step.output_dataclip_id,
            });
            // Sort by started_at to maintain order
            cachedSteps.sort((a, b) => {
              if (!a.started_at) return 1;
              if (!b.started_at) return -1;
              return (
                new Date(a.started_at).getTime() -
                new Date(b.started_at).getTime()
              );
            });
          }
        } else {
          // Cache doesn't exist yet - create it from activeRun data
          // This handles the race condition where step events arrive before
          // requestRunSteps completes. Note: This temporary cache will be
          // overwritten when requestRunSteps completes with authoritative data.
          if (draft.activeRun && draft.activeRun.id === runId) {
            draft.runStepsCache[runId] = {
              run_id: draft.activeRun.id,
              steps: draft.activeRun.steps.map(s => ({
                id: s.id,
                job_id: s.job_id,
                started_at: s.started_at,
                finished_at: s.finished_at,
                exit_reason: s.exit_reason,
                error_type: s.error_type,
                input_dataclip_id: s.input_dataclip_id,
                output_dataclip_id: s.output_dataclip_id,
              })),
              metadata: {
                starting_job_id: draft.activeRun.steps[0]?.job_id ?? null,
                starting_trigger_id: null, // Not available in RunDetail
                inserted_at: draft.activeRun.inserted_at,
                created_by_id: null, // Not available in RunDetail
                created_by_email: draft.activeRun.created_by?.email ?? null,
              },
            };
          }
        }
      }

      draft.lastUpdated = Date.now();
    });
    notify('handleStepUpdate');
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

  const setActiveRunLoading = (loading: boolean) => {
    state = produce(state, draft => {
      draft.activeRunLoading = loading;
    });
    notify('setActiveRunLoading');
  };

  const setActiveRunError = (error: string | null) => {
    state = produce(state, draft => {
      draft.activeRunError = error;
      draft.activeRunLoading = false;
    });
    notify('setActiveRunError');
  };

  const clearActiveRunError = () => {
    state = produce(state, draft => {
      draft.activeRunError = null;
    });
    notify('clearActiveRunError');
  };

  const selectStep = (stepId: string | null) => {
    state = produce(state, draft => {
      // Validate step exists in active run
      if (stepId && draft.activeRun) {
        const stepExists = draft.activeRun.steps.some(s => s.id === stepId);
        if (stepExists) {
          draft.selectedStepId = stepId;
        }
      } else {
        draft.selectedStepId = null;
      }
    });
    notify('selectStep');
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
        run?: RunSummary;
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

      // Clean up subscriber tracking if no more subscribers.
      // NOTE: We intentionally do NOT clear runStepsCache here.
      // Clearing cache on unsubscribe causes bugs with React StrictMode's
      // double-mount cycle (mount → unmount → remount), which would clear
      // the cache between mounts. The cache is small (~1KB per run) and is
      // cleaned up when the store is recreated on navigation.
      if (subscribers.size === 0) {
        Reflect.deleteProperty(draft.runStepsSubscribers, runId);
        draft.runStepsLoading.delete(runId);
      }
    });
    notify('unsubscribeFromRunSteps');
  };

  // ===========================================================================
  // ACTIVE RUN QUERIES
  // ===========================================================================

  /**
   * Get the currently active run
   */
  const getActiveRun = () => {
    const currentState = getSnapshot();
    return currentState.activeRun;
  };

  /**
   * Get the currently selected step
   */
  const getSelectedStep = () => {
    const currentState = getSnapshot();
    if (!currentState.selectedStepId || !currentState.activeRun) {
      return null;
    }
    return (
      currentState.activeRun.steps.find(
        step => step.id === currentState.selectedStepId
      ) || null
    );
  };

  /**
   * Check if active run is loading
   */
  const isActiveRunLoading = () => {
    const currentState = getSnapshot();
    return currentState.activeRunLoading;
  };

  /**
   * Get active run error
   */
  const getActiveRunError = () => {
    const currentState = getSnapshot();
    return currentState.activeRunError;
  };

  // ===========================================================================
  // ACTIVE RUN CHANNEL MANAGEMENT
  // ===========================================================================

  /**
   * Connect to and view a specific run in detail
   * Creates dedicated run:${runId} channel for real-time updates
   *
   * CRITICAL: Includes race condition prevention guards
   */
  const _viewRun = (runId: string): void => {
    // GUARD 1: Idempotency - don't reconnect to same run
    if (state.activeRunId === runId && state.activeRunChannel) {
      logger.debug('Already connected to run', runId);
      return;
    }

    // GUARD 2: Disconnect only if switching to DIFFERENT run
    if (state.activeRunChannel && state.activeRunId !== runId) {
      _switchingFromRun();
    }

    if (!_channelProvider?.socket) {
      logger.warn('Cannot view run - no channel provider');
      setActiveRunError('No connection available');
      return;
    }

    // Capture runId in closure to detect stale responses
    const requestedRunId = runId;

    state = produce(state, draft => {
      draft.activeRunId = runId;
      draft.activeRunLoading = true;
      draft.activeRunError = null;
    });
    notify('_viewRun/start');

    // Create dedicated channel: run:${runId}
    // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access, @typescript-eslint/no-explicit-any
    const channel: Channel = (_channelProvider.socket as any).channel(
      `run:${runId}`,
      {}
    );

    // Set up event handlers
    channel.on('run:updated', (payload: unknown) => {
      handleRunUpdated(payload as { run: unknown });
    });

    channel.on('step:started', (payload: unknown) => {
      handleStepStarted(payload as { step: unknown });
    });

    channel.on('step:completed', (payload: unknown) => {
      handleStepCompleted(payload as { step: unknown });
    });

    // Join channel and fetch initial data
    // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access, @typescript-eslint/no-explicit-any
    const channelJoin = (channel as any).join();
    // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access
    channelJoin.receive('ok', () => {
      // GUARD 3: Ignore stale responses from previous requests
      if (state.activeRunId !== requestedRunId) {
        logger.debug('Ignoring stale run response', {
          received: requestedRunId,
          current: state.activeRunId,
        });
        // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access, @typescript-eslint/no-explicit-any
        (channel as any).leave(); // Clean up the stale channel
        return;
      }

      logger.debug('Joined run channel', runId);

      // Fetch initial run data
      void channelRequest<{ run: unknown }>(channel, 'fetch:run', {})
        .then(response => {
          // Double-check we're still viewing this run
          if (state.activeRunId === requestedRunId) {
            handleRunReceived(response.run);

            // Only set channel after successful fetch
            state = produce(state, draft => {
              draft.activeRunChannel = channel;
            });
            notify('_viewRun/success');
          } else {
            // Switched to different run during fetch
            // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access, @typescript-eslint/no-explicit-any
            (channel as any).leave();
          }
          return undefined;
        })
        .catch(error => {
          // Only update error if still waiting for this run
          if (state.activeRunId === requestedRunId) {
            logger.error('Failed to fetch run', error);
            setActiveRunError(
              `Failed to load run: ${error instanceof Error ? error.message : 'Unknown error'}`
            );
          }
          return undefined;
        });
    });
    // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access, @typescript-eslint/no-explicit-any
    channelJoin.receive('error', (error: any) => {
      // Only update error if still waiting for this run
      if (state.activeRunId === requestedRunId) {
        logger.error('Failed to join run channel', error);
        setActiveRunError(
          // eslint-disable-next-line @typescript-eslint/no-unsafe-member-access
          `Failed to connect: ${error.reason || 'Unknown error'}`
        );
      }
      // Don't set activeRunChannel on error - leave it null
    });
  };

  const _switchingFromRun = () => {
    // Leave the curren run channel before switch happens
    if (state.activeRunChannel) {
      // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access, @typescript-eslint/no-explicit-any
      (state.activeRunChannel as any).leave();
    }

    state = produce(state, draft => {
      // only clear the necessary run stuff before switching
      draft.activeRunChannel = null;
      draft.activeRunId = null;
      draft.activeRunError = null;
    });
    notify('_switchingFromRun');
  };

  /**
   * Disconnect from active run and clean up channel
   */
  const _closeRunViewer = (): void => {
    // Leave channel before updating state (can't call methods on draft)
    if (state.activeRunChannel) {
      // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access, @typescript-eslint/no-explicit-any
      (state.activeRunChannel as any).leave();
    }

    state = produce(state, draft => {
      // Clear channel reference
      draft.activeRunChannel = null;

      // Clear active run state
      draft.activeRunId = null;
      draft.activeRun = null;
      draft.activeRunError = null;
      draft.selectedStepId = null;
    });
    notify('_closeRunViewer');
  };

  /**
   * TEST-ONLY helper to directly set active run without channel requests
   * This bypasses the normal _viewRun flow which requires Phoenix channels
   * and is intended ONLY for use in test environments
   *
   * @param run - The run to set as active
   */
  const _setActiveRunForTesting = (run: RunDetail): void => {
    state = produce(state, draft => {
      draft.activeRunId = run.id;
      draft.activeRun = run;
      draft.activeRunLoading = false;
      draft.activeRunError = null;
      // Auto-select first step if none selected
      if (!draft.selectedStepId && run.steps.length > 0) {
        draft.selectedStepId = run.steps[0]?.id || null;
      }
    });
    notify('_setActiveRunForTesting');
  };

  /**
   * Test helper: Set active run ID without setting full run data
   *
   * This is used in tests to simulate scenarios where activeRunId is set
   * but activeRun might not match (race conditions)
   *
   * @param runId - The run ID to set as active
   */
  const _setActiveRunIdForTesting = (runId: string): void => {
    state = produce(state, draft => {
      draft.activeRunId = runId;
    });
    notify('_setActiveRunIdForTesting');
  };

  /**
   * Test helper: Populate cache with run steps data
   *
   * This bypasses the normal requestRunSteps flow and directly populates
   * the cache, useful for testing cache-related logic
   *
   * @param runId - The run ID
   * @param runStepsData - The run steps data to cache
   */
  const _populateCacheForTesting = (
    runId: string,
    runStepsData: RunStepsData
  ): void => {
    state = produce(state, draft => {
      draft.runStepsCache[runId] = runStepsData;
    });
    notify('_populateCacheForTesting');
  };

  /**
   * Test helper: Trigger step update directly
   *
   * This bypasses the channel event flow and directly calls handleStepUpdate,
   * useful for testing step update logic without Phoenix channels
   *
   * @param step - The step detail to update
   */
  const _triggerStepUpdateForTesting = (step: StepDetail): void => {
    handleStepUpdate(step);
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
    getActiveRun,
    getSelectedStep,
    isActiveRunLoading,
    getActiveRunError,

    // Commands (CQS pattern)
    requestHistory,
    requestRunSteps,
    setLoading,
    setError,
    clearError,
    subscribeToRunSteps,
    unsubscribeFromRunSteps,
    selectStep,
    setActiveRunLoading,
    setActiveRunError,
    clearActiveRunError,

    // Internal methods (not part of public HistoryStore interface)
    _connectChannel,
    _viewRun,
    _closeRunViewer,
    _switchingFromRun,
    _setActiveRunForTesting,
    _setActiveRunIdForTesting,
    _populateCacheForTesting,
    _triggerStepUpdateForTesting,
  };
};

export type HistoryStoreInstance = ReturnType<typeof createHistoryStore>;
