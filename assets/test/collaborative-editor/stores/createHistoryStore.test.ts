/**
 * Tests for createHistoryStore - Core Functionality
 *
 * This test suite covers:
 * - Core store interface (subscribe/getSnapshot/withSelector)
 * - State management commands (setLoading, setError, clearError)
 * - Channel integration and request/response flow
 * - Real-time history updates
 * - Error handling for channel operations
 */

import { describe, test, expect, beforeEach } from 'vitest';
import { createHistoryStore } from '../../../js/collaborative-editor/stores/createHistoryStore';
import type { HistoryStoreInstance } from '../../../js/collaborative-editor/stores/createHistoryStore';
import type { RunStepsData } from '../../../js/collaborative-editor/types/history';

import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  waitForCondition,
} from '../mocks/phoenixChannel';
import type {
  MockPhoenixChannel,
  MockPhoenixChannelProvider,
} from '../mocks/phoenixChannel';

describe('createHistoryStore', () => {
  let store: HistoryStoreInstance;
  let mockChannel: MockPhoenixChannel;
  let mockChannelProvider: MockPhoenixChannelProvider;

  beforeEach(() => {
    store = createHistoryStore();
    mockChannel = createMockPhoenixChannel('workflow:collaborate:test');
    mockChannelProvider = createMockPhoenixChannelProvider(mockChannel);
  });

  describe('core store interface', () => {
    test('getSnapshot returns initial state', () => {
      const initialState = store.getSnapshot();

      expect(initialState.history).toEqual([]);
      expect(initialState.isLoading).toBe(false);
      expect(initialState.error).toBe(null);
      expect(initialState.lastUpdated).toBe(null);
    });

    test('subscribe/unsubscribe functionality works correctly', () => {
      let callCount = 0;

      const listener = () => {
        callCount++;
      };

      // Subscribe to changes
      const unsubscribe = store.subscribe(listener);

      // Trigger a state change
      store.setLoading(true);

      expect(callCount).toBe(1); // Listener should be called once

      // Trigger another state change
      store.setError('test error');

      expect(callCount).toBe(2); // Listener should be called twice

      // Unsubscribe and trigger change
      unsubscribe();
      store.clearError();

      expect(callCount).toBe(2); // Listener not called after unsubscribe
    });

    test('withSelector creates memoized selector with referential stability', () => {
      const selectHistory = store.withSelector(state => state.history);
      const selectIsLoading = store.withSelector(state => state.isLoading);

      // Initial calls
      const history1 = selectHistory();
      const loading1 = selectIsLoading();

      // Same calls should return same reference
      const history2 = selectHistory();
      const loading2 = selectIsLoading();

      expect(history1).toBe(history2);
      expect(loading1).toBe(loading2);

      // Change unrelated state - history selector should return same reference
      store.setLoading(true);
      const history3 = selectHistory();
      const loading3 = selectIsLoading();

      expect(history1).toBe(history3); // Unrelated state change
      expect(loading1).not.toBe(loading3); // Related state change
    });
  });

  describe('state management', () => {
    test('setLoading updates loading state and notifies subscribers', () => {
      let notificationCount = 0;

      store.subscribe(() => {
        notificationCount++;
      });

      // Set loading to true
      store.setLoading(true);

      const state1 = store.getSnapshot();
      expect(state1.isLoading).toBe(true);
      expect(notificationCount).toBe(1);

      // Set loading to false
      store.setLoading(false);

      const state2 = store.getSnapshot();
      expect(state2.isLoading).toBe(false);
      expect(notificationCount).toBe(2);
    });

    test('setError updates error state and sets loading to false', () => {
      // First set loading to true
      store.setLoading(true);
      expect(store.getSnapshot().isLoading).toBe(true);

      // Set error - should clear loading state
      const errorMessage = 'Test error message';
      store.setError(errorMessage);

      const state = store.getSnapshot();
      expect(state.error).toBe(errorMessage);
      expect(state.isLoading).toBe(false); // Setting error clears loading
    });

    test('setError with null clears error', () => {
      // Set error first
      store.setError('Test error');
      expect(store.getSnapshot().error).toBe('Test error');

      // Set error to null
      store.setError(null);
      expect(store.getSnapshot().error).toBe(null);
    });

    test('clearError removes error state', () => {
      // Set error first
      store.setError('Test error');
      expect(store.getSnapshot().error).toBe('Test error');

      // Clear error
      store.clearError();
      expect(store.getSnapshot().error).toBe(null);
    });
  });

  describe('channel integration', () => {
    test('_connectChannel registers history_updated listener', () => {
      store._connectChannel(mockChannelProvider as any);

      const handlers = (mockChannel as any)._test.getHandlers(
        'history_updated'
      );
      expect(handlers?.size).toBe(1);
    });

    test('_connectChannel returns cleanup function that unregisters listeners', () => {
      const cleanup = store._connectChannel(mockChannelProvider as any);

      // Verify listener is registered
      let handlers = (mockChannel as any)._test.getHandlers('history_updated');
      expect(handlers?.size).toBe(1);

      // Call cleanup
      cleanup();

      // Verify listener is removed
      handlers = (mockChannel as any)._test.getHandlers('history_updated');
      expect(handlers?.size).toBe(0);
    });
  });

  describe('requestHistory', () => {
    test('sets loading state before request', async () => {
      store._connectChannel(mockChannelProvider as any);

      // Mock the channel push to respond with history
      mockChannel.push = () => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => callback({ history: [] }), 10);
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        } as any;
      };

      // Start request (don't await yet)
      const promise = store.requestHistory();

      // Check loading state immediately
      expect(store.getSnapshot().isLoading).toBe(true);

      await promise;
    });

    test('handles successful response with valid history data', async () => {
      store._connectChannel(mockChannelProvider as any);

      const mockHistory = [
        {
          id: 'e2107d46-cf29-4930-b11b-cbcfcf83549d',
          state: 'success',
          last_activity: '2025-10-23T21:00:02.293382Z',
          runs: [
            {
              id: 'f3218e57-df40-4a41-b22c-dcdfdf94650e',
              state: 'success',
              error_type: null,
              started_at: '2025-10-23T20:59:58.293382Z',
              finished_at: '2025-10-23T21:00:02.293382Z',
              version: 29,
            },
          ],
        },
      ];

      // Mock the channel push to respond with history
      mockChannel.push = () => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => callback({ history: mockHistory }), 0);
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        } as any;
      };

      await store.requestHistory();

      await waitForCondition(() => !store.getSnapshot().isLoading);

      const state = store.getSnapshot();
      expect(state.history).toEqual(mockHistory);
      expect(state.isLoading).toBe(false);
      expect(state.error).toBe(null);
      expect(state.lastUpdated).toBeGreaterThan(0);
    });

    test('handles successful response with run_id parameter', async () => {
      store._connectChannel(mockChannelProvider as any);

      const runId = 'f3218e57-df40-4a41-b22c-dcdfdf94650e';
      const mockHistory = [
        {
          id: 'e2107d46-cf29-4930-b11b-cbcfcf83549d',
          state: 'success',
          last_activity: '2025-10-23T21:00:02.293382Z',
          runs: [
            {
              id: runId,
              state: 'success',
              error_type: null,
              started_at: '2025-10-23T20:59:58.293382Z',
              finished_at: '2025-10-23T21:00:02.293382Z',
              version: 29,
            },
          ],
        },
      ];

      let pushedPayload: any = null;

      mockChannel.push = (_event: string, payload: unknown) => {
        pushedPayload = payload;
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => callback({ history: mockHistory }), 0);
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        } as any;
      };

      await store.requestHistory(runId);

      await waitForCondition(() => !store.getSnapshot().isLoading);

      expect(pushedPayload).toEqual({ run_id: runId });
      expect(store.getSnapshot().history).toEqual(mockHistory);
    });

    test('handles invalid history data with Zod validation error', async () => {
      store._connectChannel(mockChannelProvider as any);

      const invalidHistory = [
        {
          id: 'not-a-uuid', // Invalid UUID
          state: 'success',
          // Missing required fields
        },
      ];

      mockChannel.push = () => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => callback({ history: invalidHistory }), 0);
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        } as any;
      };

      await store.requestHistory();

      await waitForCondition(() => !store.getSnapshot().isLoading);

      const state = store.getSnapshot();
      expect(state.error).toContain('Invalid history data');
      expect(state.isLoading).toBe(false);
      expect(state.history).toEqual([]); // Should remain empty
    });

    test('handles channel request failure', async () => {
      store._connectChannel(mockChannelProvider as any);

      mockChannel.push = () => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'error') {
              setTimeout(
                () =>
                  callback({ errors: { base: ['timeout'] }, type: 'error' }),
                0
              );
            } else if (status === 'timeout') {
              setTimeout(() => callback(), 0);
            }
            return {
              receive: (s: string, cb: (r?: unknown) => void) => {
                if (s === 'error') {
                  setTimeout(
                    () => cb({ errors: { base: ['timeout'] }, type: 'error' }),
                    0
                  );
                } else if (s === 'timeout') {
                  setTimeout(() => cb(), 0);
                }
                return { receive: () => ({}) };
              },
            };
          },
        } as any;
      };

      await store.requestHistory();

      // Wait for error state
      await waitForCondition(() => store.getSnapshot().error !== null, {
        timeout: 2000,
      });

      const state = store.getSnapshot();
      expect(state.error).toBe('Failed to request history');
      expect(state.isLoading).toBe(false);
    });

    test('handles request when no channel is connected', async () => {
      // Don't connect channel
      await store.requestHistory();

      const state = store.getSnapshot();
      expect(state.error).toBe('No connection available');
      expect(state.isLoading).toBe(false);
    });
  });

  describe('real-time updates', () => {
    test('handles work order created event', () => {
      store._connectChannel(mockChannelProvider as any);

      const newWorkOrder = {
        id: 'e2107d46-cf29-4930-b11b-cbcfcf83549d',
        state: 'pending',
        last_activity: '2025-10-23T21:00:02.293382Z',
        version: 30,
        runs: [],
      };

      (mockChannel as any)._test.emit('history_updated', {
        action: 'created',
        work_order: newWorkOrder,
      });

      const state = store.getSnapshot();
      expect(state.history).toHaveLength(1);
      expect(state.history[0]).toEqual(newWorkOrder);
    });

    test('limits history to 20 work orders when adding new one', () => {
      store._connectChannel(mockChannelProvider as any);

      // Add 20 work orders
      for (let i = 0; i < 20; i++) {
        (mockChannel as any)._test.emit('history_updated', {
          action: 'created',
          work_order: {
            id: `e2107d46-cf29-4930-b11b-cbcfcf8354${i.toString().padStart(2, '0')}`,
            state: 'success',
            last_activity: '2025-10-23T21:00:02.293382Z',
            version: i,
            runs: [],
          },
        });
      }

      expect(store.getSnapshot().history).toHaveLength(20);

      // Add 21st work order
      (mockChannel as any)._test.emit('history_updated', {
        action: 'created',
        work_order: {
          id: 'f3218e57-df40-4a41-b22c-dcdfdf946521',
          state: 'success',
          last_activity: '2025-10-23T21:00:02.293382Z',
          version: 21,
          runs: [],
        },
      });

      const state = store.getSnapshot();
      expect(state.history).toHaveLength(20);
      expect(state.history[0].id).toBe('f3218e57-df40-4a41-b22c-dcdfdf946521');
    });

    test('handles work order updated event', () => {
      store._connectChannel(mockChannelProvider as any);

      const workOrder = {
        id: 'e2107d46-cf29-4930-b11b-cbcfcf83549d',
        state: 'running',
        last_activity: '2025-10-23T21:00:02.293382Z',
        version: 30,
        runs: [],
      };

      // Add initial work order
      (mockChannel as any)._test.emit('history_updated', {
        action: 'created',
        work_order: workOrder,
      });

      // Update it
      const updatedWorkOrder = {
        ...workOrder,
        state: 'success',
        last_activity: '2025-10-23T21:05:00.000000Z',
      };

      (mockChannel as any)._test.emit('history_updated', {
        action: 'updated',
        work_order: updatedWorkOrder,
      });

      const state = store.getSnapshot();
      expect(state.history).toHaveLength(1);
      expect(state.history[0].state).toBe('success');
      expect(state.history[0].last_activity).toBe(
        '2025-10-23T21:05:00.000000Z'
      );
    });

    test('handles run created event', () => {
      store._connectChannel(mockChannelProvider as any);

      const workOrder = {
        id: 'e2107d46-cf29-4930-b11b-cbcfcf83549d',
        state: 'running',
        last_activity: '2025-10-23T21:00:02.293382Z',
        version: 30,
        runs: [],
      };

      // Add initial work order
      (mockChannel as any)._test.emit('history_updated', {
        action: 'created',
        work_order: workOrder,
      });

      // Add run
      const newRun = {
        id: 'f3218e57-df40-4a41-b22c-dcdfdf94650e',
        state: 'started',
        error_type: null,
        started_at: '2025-10-23T21:00:00.000000Z',
        finished_at: null,
      };

      (mockChannel as any)._test.emit('history_updated', {
        action: 'run_created',
        work_order_id: 'e2107d46-cf29-4930-b11b-cbcfcf83549d',
        run: newRun,
      });

      const state = store.getSnapshot();
      expect(state.history[0].runs).toHaveLength(1);
      expect(state.history[0].runs[0]).toEqual(newRun);
    });

    test('handles run updated event', () => {
      store._connectChannel(mockChannelProvider as any);

      const run = {
        id: 'f3218e57-df40-4a41-b22c-dcdfdf94650e',
        state: 'started',
        error_type: null,
        started_at: '2025-10-23T21:00:00.000000Z',
        finished_at: null,
      };

      const workOrder = {
        id: 'e2107d46-cf29-4930-b11b-cbcfcf83549d',
        state: 'running',
        last_activity: '2025-10-23T21:00:02.293382Z',
        version: 30,
        runs: [run],
      };

      // Add initial work order with run
      (mockChannel as any)._test.emit('history_updated', {
        action: 'created',
        work_order: workOrder,
      });

      // Update run
      const updatedRun = {
        ...run,
        state: 'success',
        finished_at: '2025-10-23T21:00:05.000000Z',
      };

      (mockChannel as any)._test.emit('history_updated', {
        action: 'run_updated',
        work_order_id: 'e2107d46-cf29-4930-b11b-cbcfcf83549d',
        run: updatedRun,
      });

      const state = store.getSnapshot();
      expect(state.history[0].runs[0].state).toBe('success');
      expect(state.history[0].runs[0].finished_at).toBe(
        '2025-10-23T21:00:05.000000Z'
      );
    });

    test('ignores run events for non-existent work orders', () => {
      store._connectChannel(mockChannelProvider as any);

      const newRun = {
        id: 'f3218e57-df40-4a41-b22c-dcdfdf94650e',
        state: 'started',
        error_type: null,
        started_at: '2025-10-23T21:00:00.000000Z',
        finished_at: null,
      };

      // Try to add run to non-existent work order
      (mockChannel as any)._test.emit('history_updated', {
        action: 'run_created',
        work_order_id: 'e2107d46-cf29-4930-b11b-cbcfcf83549d',
        run: newRun,
      });

      const state = store.getSnapshot();
      expect(state.history).toHaveLength(0); // No work orders added
    });
  });

  describe('run steps subscription management', () => {
    test('subscribeToRunSteps adds subscriber and fetches if not cached', async () => {
      store._connectChannel(mockChannelProvider as any);

      const mockRunSteps: RunStepsData = {
        run_id: 'run-123',
        steps: [],
        metadata: {
          starting_job_id: 'job-1',
          starting_trigger_id: null,
          inserted_at: '2025-01-08T10:00:00Z',
          created_by_id: 'user-1',
          created_by_email: 'user@example.com',
        },
      };

      mockChannel.push = () =>
        ({
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => callback(mockRunSteps), 0);
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        }) as any;

      // Subscribe
      store.subscribeToRunSteps('run-123', 'component-1');

      // Verify subscriber added
      let state = store.getSnapshot();
      expect(state.runStepsSubscribers['run-123']).toBeDefined();
      expect(state.runStepsSubscribers['run-123'].has('component-1')).toBe(
        true
      );

      // Wait for fetch to complete
      await waitForCondition(() => !store.getSnapshot().isLoading);

      // Verify data cached
      state = store.getSnapshot();
      expect(state.runStepsCache['run-123']).toEqual(mockRunSteps);
    });

    test('subscribeToRunSteps uses cached data if available', async () => {
      store._connectChannel(mockChannelProvider as any);
      const mockRunSteps: RunStepsData = {
        run_id: 'run-456',
        steps: [],
        metadata: {
          starting_job_id: 'job-2',
          starting_trigger_id: null,
          inserted_at: '2025-01-08T11:00:00Z',
          created_by_id: 'user-2',
          created_by_email: 'user2@example.com',
        },
      };

      // Pre-populate cache by fetching first
      mockChannel.push = () =>
        ({
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => callback(mockRunSteps), 0);
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        }) as any;

      await store.requestRunSteps('run-456');
      await waitForCondition(() => !store.getSnapshot().isLoading);

      // Track if push was called again
      let pushCalled = false;
      mockChannel.push = () => {
        pushCalled = true;
        return {
          receive: () => ({ receive: () => ({ receive: () => ({}) }) }),
        } as any;
      };

      // Subscribe - should use cached data
      store.subscribeToRunSteps('run-456', 'component-2');

      // Verify subscriber added but no fetch happened
      const state = store.getSnapshot();
      expect(state.runStepsSubscribers['run-456'].has('component-2')).toBe(
        true
      );
      expect(pushCalled).toBe(false);
    });

    test('multiple components can subscribe to same run', () => {
      store.subscribeToRunSteps('run-789', 'component-a');
      store.subscribeToRunSteps('run-789', 'component-b');
      store.subscribeToRunSteps('run-789', 'component-c');

      const state = store.getSnapshot();
      const subscribers = state.runStepsSubscribers['run-789'];

      expect(subscribers.size).toBe(3);
      expect(subscribers.has('component-a')).toBe(true);
      expect(subscribers.has('component-b')).toBe(true);
      expect(subscribers.has('component-c')).toBe(true);
    });

    test('unsubscribeFromRunSteps removes subscriber but keeps cache if others remain', async () => {
      store._connectChannel(mockChannelProvider as any);

      // Mock channel response
      mockChannel.push = () =>
        ({
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(
                () =>
                  callback({
                    run_id: 'run-111',
                    steps: [],
                    metadata: {
                      starting_job_id: 'job-111',
                      starting_trigger_id: null,
                      inserted_at: '2025-01-08T10:00:00Z',
                      created_by_id: 'user-111',
                      created_by_email: 'user111@example.com',
                    },
                  }),
                0
              );
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        }) as any;

      // Setup: Two subscribers (first one triggers fetch)
      store.subscribeToRunSteps('run-111', 'component-1');
      store.subscribeToRunSteps('run-111', 'component-2');

      // Wait for fetch to complete
      await waitForCondition(() => !store.getSnapshot().isLoading);

      // Unsubscribe first component
      store.unsubscribeFromRunSteps('run-111', 'component-1');

      const state = store.getSnapshot();
      const subscribers = state.runStepsSubscribers['run-111'];

      // Verify one subscriber remains
      expect(subscribers.size).toBe(1);
      expect(subscribers.has('component-2')).toBe(true);

      // Cache should still exist
      expect(state.runStepsCache['run-111']).toBeDefined();
    });

    test('unsubscribeFromRunSteps removes subscriber but preserves cache', async () => {
      store._connectChannel(mockChannelProvider as any);

      // Mock channel response
      mockChannel.push = () =>
        ({
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(
                () =>
                  callback({
                    run_id: 'run-222',
                    steps: [],
                    metadata: {
                      starting_job_id: 'job-222',
                      starting_trigger_id: null,
                      inserted_at: '2025-01-08T10:00:00Z',
                      created_by_id: 'user-222',
                      created_by_email: 'user222@example.com',
                    },
                  }),
                0
              );
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        }) as any;

      // Setup: One subscriber (triggers fetch)
      store.subscribeToRunSteps('run-222', 'component-solo');

      // Wait for fetch to complete
      await waitForCondition(() => !store.getSnapshot().isLoading);

      // Verify cache is populated before unsubscribe
      expect(store.getSnapshot().runStepsCache['run-222']).toBeDefined();

      // Unsubscribe
      store.unsubscribeFromRunSteps('run-222', 'component-solo');

      const state = store.getSnapshot();

      // Subscriber tracking should be cleaned up
      expect(state.runStepsSubscribers['run-222']).toBeUndefined();
      // Cache should be preserved (not cleared on unsubscribe)
      // This prevents bugs with React StrictMode's double-mount cycle
      expect(state.runStepsCache['run-222']).toBeDefined();
      expect(state.runStepsCache['run-222']?.run_id).toBe('run-222');
    });

    test('handleHistoryUpdated invalidates cache for subscribed runs', async () => {
      store._connectChannel(mockChannelProvider as any);

      // Mock initial fetch
      const oldRunSteps: RunStepsData = {
        run_id: 'run-333',
        steps: [{ id: 'step-old' } as any],
        metadata: {
          starting_job_id: 'job-3',
          starting_trigger_id: null,
          inserted_at: '2025-01-08T12:00:00Z',
          created_by_id: 'user-3',
          created_by_email: 'user3@example.com',
        },
      };

      mockChannel.push = () =>
        ({
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => callback(oldRunSteps), 0);
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        }) as any;

      // Setup: Subscribe (triggers initial fetch)
      store.subscribeToRunSteps('run-333', 'component-1');
      await waitForCondition(() => !store.getSnapshot().isLoading);

      // Mock fetch for refetch with new data
      const newRunSteps: RunStepsData = {
        run_id: 'run-333',
        steps: [{ id: 'step-new' } as any],
        metadata: {
          starting_job_id: 'job-3',
          starting_trigger_id: null,
          inserted_at: '2025-01-08T12:00:00Z',
          created_by_id: 'user-3',
          created_by_email: 'user3@example.com',
        },
      };

      mockChannel.push = () =>
        ({
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => callback(newRunSteps), 0);
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        }) as any;

      // Emit run_updated event
      (mockChannel as any)._test.emit('history_updated', {
        action: 'run_updated',
        run: { id: 'run-333', state: 'success' },
        work_order_id: 'wo-1',
      });

      // Wait for refetch
      await waitForCondition(() => {
        const state = store.getSnapshot();
        return state.runStepsCache['run-333']?.steps?.[0]?.id === 'step-new';
      });

      // Verify cache was updated
      const state = store.getSnapshot();
      expect(state.runStepsCache['run-333'].steps[0].id).toBe('step-new');
    });

    test('handleHistoryUpdated does not refetch for unsubscribed runs', () => {
      store._connectChannel(mockChannelProvider as any);

      // Track if fetch was called
      let fetchCalled = false;
      mockChannel.push = () => {
        fetchCalled = true;
        return {
          receive: () => ({ receive: () => ({ receive: () => ({}) }) }),
        } as any;
      };

      // Emit run_updated for run with no subscribers
      (mockChannel as any)._test.emit('history_updated', {
        action: 'run_updated',
        run: { id: 'run-no-subs', state: 'success' },
        work_order_id: 'wo-2',
      });

      // Should not fetch
      expect(fetchCalled).toBe(false);
    });

    test('runStepsLoading prevents duplicate concurrent fetches', async () => {
      store._connectChannel(mockChannelProvider as any);

      let fetchCount = 0;
      mockChannel.push = () => {
        fetchCount++;
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(
                () =>
                  callback({
                    run_id: 'run-444',
                    steps: [],
                    metadata: {
                      starting_job_id: 'job-4',
                      starting_trigger_id: null,
                      inserted_at: '2025-01-08T13:00:00Z',
                      created_by_id: 'user-4',
                      created_by_email: 'user4@example.com',
                    },
                  }),
                50
              );
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        } as any;
      };

      // Subscribe twice quickly (before first fetch completes)
      store.subscribeToRunSteps('run-444', 'component-1');
      store.subscribeToRunSteps('run-444', 'component-2');

      // Should only fetch once
      expect(fetchCount).toBe(1);

      // Wait for fetch to complete
      await waitForCondition(() => !store.getSnapshot().isLoading);

      // Verify both subscribers exist
      const state = store.getSnapshot();
      expect(state.runStepsSubscribers['run-444'].size).toBe(2);
    });
  });

  describe('active run management', () => {
    test('_closeRunViewer clears activeRun state', () => {
      // Manually set up some active run state using internal test helper
      store._setActiveRunForTesting({
        id: 'run-to-clear',
        state: 'success',
        steps: [{ id: 'step-1', job_id: 'job-1' }],
      } as any);

      // Verify activeRun is set
      let state = store.getSnapshot();
      expect(state.activeRun).not.toBeNull();
      expect(state.activeRun?.id).toBe('run-to-clear');

      // Close the run viewer
      store._closeRunViewer();

      // Verify activeRun is cleared
      state = store.getSnapshot();
      expect(state.activeRun).toBeNull();
      expect(state.activeRunId).toBeNull();
      expect(state.selectedStepId).toBeNull();
    });

    test('_closeRunViewer clears activeRunError', () => {
      // Set up active run with an error
      store._setActiveRunForTesting({
        id: 'run-with-error',
        state: 'failed',
        steps: [],
      } as any);

      // Verify activeRun is set
      let state = store.getSnapshot();
      expect(state.activeRun).not.toBeNull();

      // Close the run viewer
      store._closeRunViewer();

      // Verify all active run state is cleared
      state = store.getSnapshot();
      expect(state.activeRun).toBeNull();
      expect(state.activeRunError).toBeNull();
    });
  });

  describe('initial run data pre-population', () => {
    test('createHistoryStore with initial run data pre-populates cache', () => {
      const initialRunData: RunStepsData = {
        run_id: 'server-provided-run',
        steps: [
          {
            id: 'step-1',
            job_id: 'job-1',
            exit_reason: 'success',
            error_type: null,
            started_at: '2025-01-08T10:00:00Z',
            finished_at: '2025-01-08T10:00:05Z',
            input_dataclip_id: 'dc-1',
          },
        ],
        metadata: {
          starting_job_id: 'job-1',
          starting_trigger_id: null,
          inserted_at: '2025-01-08T10:00:00Z',
          created_by_id: 'user-1',
          created_by_email: 'user@example.com',
        },
      };

      // Create store with initial data
      const storeWithInitialData = createHistoryStore({
        initialRunData,
      });

      const state = storeWithInitialData.getSnapshot();

      // Cache should be pre-populated
      expect(state.runStepsCache['server-provided-run']).toBeDefined();
      expect(state.runStepsCache['server-provided-run']).toEqual(
        initialRunData
      );
    });

    test('createHistoryStore without initial data has empty cache', () => {
      const storeWithoutInitialData = createHistoryStore();

      const state = storeWithoutInitialData.getSnapshot();

      // Cache should be empty
      expect(Object.keys(state.runStepsCache)).toHaveLength(0);
    });

    test('createHistoryStore with null initial data has empty cache', () => {
      const storeWithNullData = createHistoryStore({ initialRunData: null });

      const state = storeWithNullData.getSnapshot();

      // Cache should be empty
      expect(Object.keys(state.runStepsCache)).toHaveLength(0);
    });

    test('pre-populated cache survives React StrictMode double-mount', async () => {
      // This test simulates React StrictMode's mount-unmount-mount cycle
      const initialRunData: RunStepsData = {
        run_id: 'strict-mode-run',
        steps: [],
        metadata: {
          starting_job_id: 'job-1',
          starting_trigger_id: null,
          inserted_at: '2025-01-08T10:00:00Z',
          created_by_id: 'user-1',
          created_by_email: 'user@example.com',
        },
      };

      const storeWithInitialData = createHistoryStore({ initialRunData });

      // First mount: subscribe
      storeWithInitialData.subscribeToRunSteps(
        'strict-mode-run',
        'component-react'
      );
      expect(
        storeWithInitialData.getSnapshot().runStepsCache['strict-mode-run']
      ).toBeDefined();

      // StrictMode unmount: unsubscribe
      storeWithInitialData.unsubscribeFromRunSteps(
        'strict-mode-run',
        'component-react'
      );

      // Cache should still exist (not cleared on unsubscribe)
      expect(
        storeWithInitialData.getSnapshot().runStepsCache['strict-mode-run']
      ).toBeDefined();

      // Second mount: subscribe again
      storeWithInitialData.subscribeToRunSteps(
        'strict-mode-run',
        'component-react'
      );

      // Cache should still be available
      const finalState = storeWithInitialData.getSnapshot();
      expect(finalState.runStepsCache['strict-mode-run']).toEqual(
        initialRunData
      );
    });
  });

  describe('step events race condition handling', () => {
    test('step event initializes cache from activeRun when cache does not exist', () => {
      // Setup: activeRun loaded with initial steps, cache empty, no channel
      const mockActiveRun = {
        id: 'run-race-1',
        work_order_id: 'wo-1',
        work_order: {
          id: 'wo-1',
          workflow_id: 'wf-1',
        },
        state: 'running' as const,
        created_by: {
          email: 'user@example.com',
        },
        starting_trigger: null,
        started_at: '2025-01-16T10:00:00Z',
        finished_at: null,
        inserted_at: '2025-01-16T10:00:00Z',
        steps: [
          {
            id: 'step-1',
            job_id: 'job-1',
            exit_reason: null,
            error_type: null,
            started_at: '2025-01-16T10:00:01Z',
            finished_at: null,
            input_dataclip_id: 'dc-1',
            output_dataclip_id: null,
          },
          {
            id: 'step-2',
            job_id: 'job-2',
            exit_reason: null,
            error_type: null,
            started_at: null,
            finished_at: null,
            input_dataclip_id: null,
            output_dataclip_id: null,
          },
        ],
      };

      store._setActiveRunForTesting(mockActiveRun as any);

      // Set activeRunId manually
      store._setActiveRunIdForTesting('run-race-1');

      // Verify cache is empty
      expect(store.getSnapshot().runStepsCache['run-race-1']).toBeUndefined();

      // Trigger: step:completed event arrives before requestRunSteps completes
      store._triggerStepUpdateForTesting({
        id: 'step-1',
        job_id: 'job-1',
        exit_reason: 'success',
        error_type: null,
        started_at: '2025-01-16T10:00:01Z',
        finished_at: '2025-01-16T10:00:05Z',
        input_dataclip_id: 'dc-1',
        output_dataclip_id: 'dc-out-1',
      });

      // Assert: cache initialized with all steps from activeRun
      const state = store.getSnapshot();
      expect(state.runStepsCache['run-race-1']).toBeDefined();
      expect(state.runStepsCache['run-race-1'].run_id).toBe('run-race-1');
      expect(state.runStepsCache['run-race-1'].steps).toHaveLength(2);

      // Verify metadata is populated
      const metadata = state.runStepsCache['run-race-1'].metadata;
      expect(metadata.starting_job_id).toBe('job-1');
      expect(metadata.starting_trigger_id).toBeNull();
      expect(metadata.inserted_at).toBe('2025-01-16T10:00:00Z');
      expect(metadata.created_by_id).toBeNull();
      expect(metadata.created_by_email).toBe('user@example.com');

      // Verify step-1 was updated by the step event (has output_dataclip_id)
      // and step-2 kept its original value from activeRun
      expect(state.runStepsCache['run-race-1'].steps[0].id).toBe('step-1');
      expect(
        state.runStepsCache['run-race-1'].steps[0].output_dataclip_id
      ).toBe('dc-out-1');
      expect(state.runStepsCache['run-race-1'].steps[1].id).toBe('step-2');
      expect(
        state.runStepsCache['run-race-1'].steps[1].output_dataclip_id
      ).toBe(null);
    });

    test('step event adds new step to existing cache and sorts by started_at', () => {
      const mockRunSteps: RunStepsData = {
        run_id: 'run-race-2',
        steps: [
          {
            id: 'step-1',
            job_id: 'job-1',
            exit_reason: 'success',
            error_type: null,
            started_at: '2025-01-16T10:00:00Z',
            finished_at: '2025-01-16T10:00:02Z',
            input_dataclip_id: 'dc-1',
            output_dataclip_id: 'dc-out-1',
          },
          {
            id: 'step-2',
            job_id: 'job-2',
            exit_reason: 'success',
            error_type: null,
            started_at: '2025-01-16T10:00:03Z',
            finished_at: '2025-01-16T10:00:05Z',
            input_dataclip_id: 'dc-2',
            output_dataclip_id: 'dc-out-2',
          },
        ],
        metadata: {
          starting_job_id: 'job-1',
          starting_trigger_id: null,
          inserted_at: '2025-01-16T10:00:00Z',
          created_by_id: 'user-1',
          created_by_email: 'user@example.com',
        },
      };

      // Pre-populate cache
      store._populateCacheForTesting('run-race-2', mockRunSteps);
      store._setActiveRunIdForTesting('run-race-2');

      // Verify initial cache state
      expect(
        store.getSnapshot().runStepsCache['run-race-2'].steps
      ).toHaveLength(2);

      // Trigger: step:completed event for NEW step-3
      store._triggerStepUpdateForTesting({
        id: 'step-3',
        job_id: 'job-3',
        exit_reason: 'success',
        error_type: null,
        started_at: '2025-01-16T10:00:06Z',
        finished_at: '2025-01-16T10:00:08Z',
        input_dataclip_id: 'dc-3',
        output_dataclip_id: 'dc-out-3',
      });

      // Assert: new step added to cache
      const state = store.getSnapshot();
      expect(state.runStepsCache['run-race-2'].steps).toHaveLength(3);

      // Verify steps are sorted by started_at
      const steps = state.runStepsCache['run-race-2'].steps;
      expect(steps[0].id).toBe('step-1');
      expect(steps[1].id).toBe('step-2');
      expect(steps[2].id).toBe('step-3');

      // Verify new step has correct data
      expect(steps[2].job_id).toBe('job-3');
      expect(steps[2].output_dataclip_id).toBe('dc-out-3');
    });

    test('step event with null started_at is sorted to end', () => {
      const mockRunSteps: RunStepsData = {
        run_id: 'run-race-3',
        steps: [
          {
            id: 'step-1',
            job_id: 'job-1',
            exit_reason: 'success',
            error_type: null,
            started_at: '2025-01-16T10:00:00Z',
            finished_at: '2025-01-16T10:00:02Z',
            input_dataclip_id: 'dc-1',
            output_dataclip_id: 'dc-out-1',
          },
        ],
        metadata: {
          starting_job_id: 'job-1',
          starting_trigger_id: null,
          inserted_at: '2025-01-16T10:00:00Z',
          created_by_id: 'user-1',
          created_by_email: 'user@example.com',
        },
      };

      store._populateCacheForTesting('run-race-3', mockRunSteps);
      store._setActiveRunIdForTesting('run-race-3');

      // Trigger: step event with null started_at (not yet started)
      store._triggerStepUpdateForTesting({
        id: 'step-pending',
        job_id: 'job-pending',
        exit_reason: null,
        error_type: null,
        started_at: null,
        finished_at: null,
        input_dataclip_id: null,
        output_dataclip_id: null,
      });

      // Assert: step with null started_at is at the end
      const state = store.getSnapshot();
      const steps = state.runStepsCache['run-race-3'].steps;
      expect(steps).toHaveLength(2);
      expect(steps[0].id).toBe('step-1');
      expect(steps[1].id).toBe('step-pending');
    });

    test('step event updates existing step in cache', () => {
      const mockRunSteps: RunStepsData = {
        run_id: 'run-race-4',
        steps: [
          {
            id: 'step-in-progress',
            job_id: 'job-1',
            exit_reason: null,
            error_type: null,
            started_at: '2025-01-16T10:00:00Z',
            finished_at: null,
            input_dataclip_id: 'dc-1',
            output_dataclip_id: null,
          },
        ],
        metadata: {
          starting_job_id: 'job-1',
          starting_trigger_id: null,
          inserted_at: '2025-01-16T10:00:00Z',
          created_by_id: 'user-1',
          created_by_email: 'user@example.com',
        },
      };

      store._populateCacheForTesting('run-race-4', mockRunSteps);
      store._setActiveRunIdForTesting('run-race-4');

      // Trigger: step:completed event for existing step
      store._triggerStepUpdateForTesting({
        id: 'step-in-progress',
        job_id: 'job-1',
        exit_reason: 'success',
        error_type: null,
        started_at: '2025-01-16T10:00:00Z',
        finished_at: '2025-01-16T10:00:05Z',
        input_dataclip_id: 'dc-1',
        output_dataclip_id: 'dc-out-1',
      });

      // Assert: existing step updated (not duplicated)
      const state = store.getSnapshot();
      const steps = state.runStepsCache['run-race-4'].steps;
      expect(steps).toHaveLength(1);
      expect(steps[0].exit_reason).toBe('success');
      expect(steps[0].finished_at).toBe('2025-01-16T10:00:05Z');
      expect(steps[0].output_dataclip_id).toBe('dc-out-1');
    });

    test('requestRunSteps overwrites cache initialized from activeRun', async () => {
      store._connectChannel(mockChannelProvider as any);

      // Setup: activeRun with incomplete data
      const mockActiveRun = {
        id: 'run-race-5',
        work_order_id: 'wo-1',
        work_order: {
          id: 'wo-1',
          workflow_id: 'wf-1',
        },
        state: 'running' as const,
        created_by: {
          email: 'user@example.com',
        },
        starting_trigger: null,
        started_at: '2025-01-16T10:00:00Z',
        finished_at: null,
        inserted_at: '2025-01-16T10:00:00Z',
        steps: [
          {
            id: 'step-1',
            job_id: 'job-1',
            exit_reason: null,
            error_type: null,
            started_at: '2025-01-16T10:00:01Z',
            finished_at: null,
            input_dataclip_id: 'dc-1',
            output_dataclip_id: null,
          },
        ],
      };

      store._setActiveRunForTesting(mockActiveRun as any);
      store._setActiveRunIdForTesting('run-race-5');

      // Trigger: step event initializes cache from activeRun
      store._triggerStepUpdateForTesting({
        id: 'step-1',
        job_id: 'job-1',
        exit_reason: 'success',
        error_type: null,
        started_at: '2025-01-16T10:00:01Z',
        finished_at: '2025-01-16T10:00:05Z',
        input_dataclip_id: 'dc-1',
        output_dataclip_id: 'dc-out-1',
      });

      // Verify cache initialized
      let state = store.getSnapshot();
      expect(state.runStepsCache['run-race-5']).toBeDefined();
      expect(
        state.runStepsCache['run-race-5'].metadata.created_by_id
      ).toBeNull();

      // Mock authoritative response from requestRunSteps
      const authoritativeRunSteps: RunStepsData = {
        run_id: 'run-race-5',
        steps: [
          {
            id: 'step-1',
            job_id: 'job-1',
            exit_reason: 'success',
            error_type: null,
            started_at: '2025-01-16T10:00:01Z',
            finished_at: '2025-01-16T10:00:05Z',
            input_dataclip_id: 'dc-1',
            output_dataclip_id: 'dc-out-1',
          },
        ],
        metadata: {
          starting_job_id: 'job-1',
          starting_trigger_id: null,
          inserted_at: '2025-01-16T10:00:00Z',
          created_by_id: 'user-123', // Authoritative data has this
          created_by_email: 'user@example.com',
        },
      };

      mockChannel.push = () =>
        ({
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => callback(authoritativeRunSteps), 0);
            }
            return { receive: () => ({ receive: () => ({}) }) };
          },
        }) as any;

      // Trigger: requestRunSteps completes
      await store.requestRunSteps('run-race-5');
      await waitForCondition(() => !store.getSnapshot().isLoading);

      // Assert: cache overwritten with authoritative data
      state = store.getSnapshot();
      expect(state.runStepsCache['run-race-5'].metadata.created_by_id).toBe(
        'user-123'
      );
    });

    test('step event does not initialize cache when activeRun does not match', () => {
      // Setup: activeRun for different run
      const mockActiveRun = {
        id: 'run-different',
        work_order_id: 'wo-1',
        work_order: {
          id: 'wo-1',
          workflow_id: 'wf-1',
        },
        state: 'running' as const,
        created_by: null,
        starting_trigger: null,
        started_at: '2025-01-16T10:00:00Z',
        finished_at: null,
        inserted_at: '2025-01-16T10:00:00Z',
        steps: [],
      };

      store._setActiveRunForTesting(mockActiveRun as any);
      store._setActiveRunIdForTesting('run-target'); // Different from activeRun.id

      // Trigger: step event for run-target
      store._triggerStepUpdateForTesting({
        id: 'step-1',
        job_id: 'job-1',
        exit_reason: 'success',
        error_type: null,
        started_at: '2025-01-16T10:00:01Z',
        finished_at: '2025-01-16T10:00:05Z',
        input_dataclip_id: 'dc-1',
        output_dataclip_id: 'dc-out-1',
      });

      // Assert: cache not initialized (mismatch between activeRunId and activeRun.id)
      const state = store.getSnapshot();
      expect(state.runStepsCache['run-target']).toBeUndefined();
    });
  });
});
