import { produce } from 'immer';
import type { Channel } from 'phoenix';
import type { PhoenixChannelProvider } from 'y-phoenix-channel';

import _logger from '#/utils/logger';

import { channelRequest } from '../hooks/useChannel';
import {
  type Run,
  type RunState,
  type RunStore,
  type Step,
  RunSchema,
  StepSchema,
} from '../types/run';

import { createWithSelector } from './common';
import { wrapStoreWithDevTools } from './devtools';

const logger = _logger.ns('RunStore').seal();

export const createRunStore = (): RunStore => {
  // 1. Initialize state with Immer
  let state: RunState = produce(
    {
      currentRun: null,
      selectedStepId: null,
      isLoading: false,
      error: null,
      lastUpdated: null,
    } as RunState,
    draft => draft
  );

  const listeners = new Set<() => void>();

  // 2. Setup Redux DevTools
  const devtools = wrapStoreWithDevTools({
    name: 'RunStore',
    excludeKeys: [],
    maxAge: 100,
  });

  // 3. Notify function - triggers React re-renders
  const notify = (actionName: string = 'stateChange') => {
    devtools.notifyWithAction(actionName, () => state);
    listeners.forEach(listener => listener());
  };

  // 4. Core interface - useSyncExternalStore
  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  const getSnapshot = (): RunState => state;

  const withSelector = createWithSelector(getSnapshot);

  // 5. Channel message handlers
  const handleRunReceived = (rawData: unknown) => {
    const result = RunSchema.safeParse(rawData);

    if (result.success) {
      const run = result.data;

      state = produce(state, draft => {
        draft.currentRun = run;
        draft.isLoading = false;
        draft.error = null;
        draft.lastUpdated = Date.now();

        // Select first step by default if none selected
        if (!draft.selectedStepId && run.steps.length > 0) {
          draft.selectedStepId = run.steps[0]?.id;
        }
      });
      notify('handleRunReceived');
    } else {
      logger.error('Failed to parse run', result.error);
      state = produce(state, draft => {
        draft.isLoading = false;
        draft.error = `Invalid run data: ${result.error.message}`;
      });
      notify('runError');
    }
  };

  const handleRunUpdated = (rawData: unknown) => {
    const result = RunSchema.safeParse(rawData);

    if (result.success) {
      const updates = result.data;

      state = produce(state, draft => {
        if (draft.currentRun && draft.currentRun.id === updates.id) {
          // Merge updates while preserving steps array
          draft.currentRun = {
            ...draft.currentRun,
            ...updates,
          };
          draft.lastUpdated = Date.now();
        }
      });
      notify('handleRunUpdated');
    }
  };

  const handleStepStarted = (rawData: unknown) => {
    const result = StepSchema.safeParse(rawData);

    if (result.success) {
      addOrUpdateStep(result.data);
    }
  };

  const handleStepCompleted = (rawData: unknown) => {
    const result = StepSchema.safeParse(rawData);

    if (result.success) {
      addOrUpdateStep(result.data);
    }
  };

  // 6. State mutation commands
  const setRun = (run: Run) => {
    state = produce(state, draft => {
      draft.currentRun = run;
      draft.lastUpdated = Date.now();
    });
    notify('setRun');
  };

  const updateRunState = (updates: Partial<Run>) => {
    state = produce(state, draft => {
      if (draft.currentRun) {
        Object.assign(draft.currentRun, updates);
        draft.lastUpdated = Date.now();
      }
    });
    notify('updateRunState');
  };

  const addOrUpdateStep = (step: Step) => {
    state = produce(state, draft => {
      if (!draft.currentRun) return;

      const index = draft.currentRun.steps.findIndex(s => s.id === step.id);

      if (index >= 0) {
        // Update existing step
        draft.currentRun.steps[index] = step;
      } else {
        // Add new step and sort by started_at
        draft.currentRun.steps.push(step);
        draft.currentRun.steps.sort((a, b) => {
          if (!a.started_at) return 1;
          if (!b.started_at) return -1;
          return (
            new Date(a.started_at).getTime() - new Date(b.started_at).getTime()
          );
        });
      }

      draft.lastUpdated = Date.now();
    });
    notify('addOrUpdateStep');
  };

  const selectStep = (stepId: string | null) => {
    state = produce(state, draft => {
      draft.selectedStepId = stepId;
    });
    notify('selectStep');
  };

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

  const clear = () => {
    state = produce(state, draft => {
      draft.currentRun = null;
      draft.selectedStepId = null;
      draft.isLoading = false;
      draft.error = null;
    });
    notify('clear');
  };

  // 7. Query helpers
  const findStepById = (id: string): Step | null => {
    if (!state.currentRun) return null;
    return state.currentRun.steps.find(step => step.id === id) || null;
  };

  const getSelectedStep = (): Step | null => {
    if (!state.selectedStepId) return null;
    return findStepById(state.selectedStepId);
  };

  // 8. Channel integration
  let currentChannel: Channel | null = null;
  let currentRunId: string | null = null;

  const connectToRun = (provider: PhoenixChannelProvider, runId: string) => {
    // Disconnect from previous run if any
    if (currentChannel && currentRunId !== runId) {
      disconnectFromRun();
    }

    // Don't reconnect to same run
    if (currentRunId === runId && currentChannel) {
      logger.debug('Already connected to run', runId);
      return () => {}; // Return no-op cleanup to prevent disconnect
    }

    currentRunId = runId;

    // Create channel
    const channel = (provider.socket as any).channel(`run:${runId}`, {});
    currentChannel = channel;

    // Setup event handlers
    channel.on('run:updated', (payload: any) => {
      handleRunUpdated(payload.run);
    });

    channel.on('step:started', (payload: any) => {
      handleStepStarted(payload.step);
    });

    channel.on('step:completed', (payload: any) => {
      handleStepCompleted(payload.step);
    });

    // Join channel and fetch initial data
    setLoading(true);
    clearError();

    channel
      .join()
      .receive('ok', () => {
        logger.debug('Joined run channel', runId);

        // Fetch initial run data
        void channelRequest<{ run: unknown }>(channel, 'fetch:run', {})
          .then(response => {
            handleRunReceived(response.run);
          })
          .catch(error => {
            logger.error('Failed to fetch run', error);
            setError(
              `Failed to load run: ${error instanceof Error ? error.message : 'Unknown error'}`
            );
          });
      })
      .receive('error', (error: any) => {
        logger.error('Failed to join run channel', error);
        setError(`Failed to connect: ${error.reason || 'Unknown error'}`);
      });

    devtools.connect();

    // Return cleanup function
    return () => {
      disconnectFromRun();
    };
  };

  const disconnectFromRun = () => {
    if (currentChannel) {
      (currentChannel as any).leave();
      currentChannel = null;
    }
    currentRunId = null;
    clear();
    devtools.disconnect();
  };

  // 9. Return public interface
  return {
    subscribe,
    getSnapshot,
    withSelector,
    setRun,
    updateRunState,
    addOrUpdateStep,
    selectStep,
    setLoading,
    setError,
    clearError,
    clear,
    findStepById,
    getSelectedStep,
    _connectToRun: connectToRun,
    _disconnectFromRun: disconnectFromRun,
  };
};

export type RunStoreInstance = ReturnType<typeof createRunStore>;
