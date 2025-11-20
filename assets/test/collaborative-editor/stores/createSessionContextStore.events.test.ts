/**
 * Tests for createSessionContextStore - Event Handling & Performance
 *
 * This test suite covers:
 * - Real-time event handling (session_context, session_context_updated)
 * - Channel event listener setup and cleanup
 * - Timestamp tracking (lastUpdated)
 * - Selector performance and referential stability
 */

import { describe, expect, test } from 'vitest';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';

import {
  createMockSessionContext,
  mockAppConfig,
  mockProjectContext,
  mockSessionContextResponse,
  mockUnauthenticatedSessionContext,
  mockUpdatedSessionContext,
  mockUserContext,
} from '../__helpers__/sessionContextFactory';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  waitForCondition,
  type MockPhoenixChannel,
} from '../mocks/phoenixChannel';

describe('createSessionContextStore - Event Handling & Performance', () => {
  describe('event handling', () => {
    test('channel session_context events are processed correctly', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      // Set up the initial channel response for get_context
      mockChannel.push = (_event: string, _payload: unknown) => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => {
                callback(mockUnauthenticatedSessionContext);
              }, 0);
            }
            return {
              receive: () => {
                return { receive: () => ({ receive: () => ({}) }) };
              },
            };
          },
        };
      };

      // Connect to channel
      const cleanup = store._connectChannel(mockProvider);

      // Verify initial state
      const initialState = store.getSnapshot();
      expect(initialState.user).toBe(null);

      // Simulate session_context event from server (user logged in)
      const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
        _test: { emit: (event: string, message: unknown) => void };
      };
      mockChannelWithTest._test.emit(
        'session_context',
        mockSessionContextResponse
      );

      // Wait for the event to be processed
      await waitForCondition(() => store.getSnapshot().user !== null);

      const state = store.getSnapshot();
      expect(state.user).toEqual(mockUserContext);
      expect(state.project).toEqual(mockProjectContext);
      expect(state.config).toEqual(mockAppConfig);
      expect(state.error).toBe(null);

      // Cleanup
      cleanup();
    });

    test('channel session_context_updated events are processed correctly', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      // Set up the initial channel response
      mockChannel.push = (_event: string, _payload: unknown) => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => {
                callback(mockSessionContextResponse);
              }, 0);
            }
            return {
              receive: () => {
                return { receive: () => ({ receive: () => ({}) }) };
              },
            };
          },
        };
      };

      // Connect to channel
      const cleanup = store._connectChannel(mockProvider);

      // Wait for initial state to be loaded
      await waitForCondition(() => store.getSnapshot().user !== null);

      // Verify initial state
      const initialState = store.getSnapshot();
      expect(initialState.user).toEqual(mockUserContext);

      // Simulate session_context_updated event from server
      const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
        _test: { emit: (event: string, message: unknown) => void };
      };
      mockChannelWithTest._test.emit(
        'session_context_updated',
        mockUpdatedSessionContext
      );

      // Wait for the updated event to be processed
      await waitForCondition(
        () =>
          store.getSnapshot().user?.id === mockUpdatedSessionContext.user?.id
      );

      const state = store.getSnapshot();
      expect(state.user).toEqual(mockUpdatedSessionContext.user);
      expect(state.project).toEqual(mockUpdatedSessionContext.project);
      expect(state.config).toEqual(mockUpdatedSessionContext.config);

      // Cleanup
      cleanup();
    });

    test('connectChannel sets up event listeners and requests session context', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      // Mock the channel push method to simulate successful response
      mockChannel.push = (_event: string, _payload: unknown) => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => {
                callback(mockSessionContextResponse);
              }, 0);
            }
            return {
              receive: () => {
                return { receive: () => ({ receive: () => ({}) }) };
              },
            };
          },
        };
      };

      // Connect to channel
      const cleanup = store._connectChannel(mockProvider);

      // Wait for session context to be loaded
      await waitForCondition(() => store.getSnapshot().user !== null);

      // Verify session context was loaded
      const state = store.getSnapshot();
      expect(state.user).toEqual(mockUserContext);
      expect(state.project).toEqual(mockProjectContext);
      expect(state.config).toEqual(mockAppConfig);

      // Test real-time updates
      const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
        _test: { emit: (event: string, message: unknown) => void };
      };
      mockChannelWithTest._test.emit(
        'session_context_updated',
        mockUpdatedSessionContext
      );

      // Wait for the updated event to be processed
      await waitForCondition(
        () =>
          store.getSnapshot().user?.id === mockUpdatedSessionContext.user?.id
      );

      const updatedState = store.getSnapshot();
      expect(updatedState.user).toEqual(mockUpdatedSessionContext.user);
      expect(updatedState.project).toEqual(mockUpdatedSessionContext.project);
      expect(updatedState.config).toEqual(mockUpdatedSessionContext.config);

      // Cleanup
      cleanup();
    });

    test('handleSessionContextReceived updates lastUpdated timestamp', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      const timestampBefore = Date.now();

      mockChannel.push = (_event: string, _payload: unknown) => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => {
                callback(mockSessionContextResponse);
              }, 0);
            }
            return {
              receive: () => {
                return { receive: () => ({ receive: () => ({}) }) };
              },
            };
          },
        };
      };

      store._connectChannel(mockProvider);
      await store.requestSessionContext();

      const state = store.getSnapshot();
      expect(state.lastUpdated).not.toBe(null);
      expect(
        state.lastUpdated ? state.lastUpdated >= timestampBefore : false
      ).toBe(true);
    });

    test('handleSessionContextUpdated updates lastUpdated timestamp', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      mockChannel.push = (_event: string, _payload: unknown) => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => {
                callback(mockSessionContextResponse);
              }, 0);
            }
            return {
              receive: () => {
                return { receive: () => ({ receive: () => ({}) }) };
              },
            };
          },
        };
      };

      store._connectChannel(mockProvider);

      // Wait for initial data to be loaded
      await waitForCondition(() => store.getSnapshot().lastUpdated !== null);

      const firstTimestamp = store.getSnapshot().lastUpdated;

      // Small delay before triggering update
      await new Promise(resolve => setTimeout(resolve, 10));

      const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
        _test: { emit: (event: string, message: unknown) => void };
      };
      mockChannelWithTest._test.emit(
        'session_context_updated',
        mockUpdatedSessionContext
      );

      // Wait for the updated event to be processed
      await waitForCondition(
        () => store.getSnapshot().lastUpdated !== firstTimestamp
      );

      const secondTimestamp = store.getSnapshot().lastUpdated;
      expect(secondTimestamp).not.toBe(null);
      expect(
        secondTimestamp && firstTimestamp
          ? secondTimestamp >= firstTimestamp
          : false
      ).toBe(true);
    });

    test('channel cleanup removes event listeners', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      mockChannel.push = (_event: string, _payload: unknown) => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => {
                callback(mockSessionContextResponse);
              }, 0);
            }
            return {
              receive: () => {
                return { receive: () => ({ receive: () => ({}) }) };
              },
            };
          },
        };
      };

      // Connect to channel
      const cleanup = store._connectChannel(mockProvider);

      // Wait for initial connection to be established
      await waitForCondition(() => store.getSnapshot().user !== null);

      // Verify handlers are registered
      const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
        _test: { getHandlers: (event: string) => Set<unknown> | undefined };
      };
      expect(
        mockChannelWithTest._test.getHandlers('session_context')?.size
      ).toBe(1);
      expect(
        mockChannelWithTest._test.getHandlers('session_context_updated')?.size
      ).toBe(1);

      // Cleanup
      cleanup();

      // Verify handlers are removed
      expect(
        mockChannelWithTest._test.getHandlers('session_context')?.size
      ).toBe(0);
      expect(
        mockChannelWithTest._test.getHandlers('session_context_updated')?.size
      ).toBe(0);
    });
  });

  describe('selector performance', () => {
    test('withSelector provides optimized access to state', () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      mockChannel.push = (_event: string, _payload: unknown) => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => {
                callback(mockSessionContextResponse);
              }, 0);
            }
            return {
              receive: () => {
                return { receive: () => ({ receive: () => ({}) }) };
              },
            };
          },
        };
      };

      store._connectChannel(mockProvider);

      // Create selectors
      const selectUser = store.withSelector(state => state.user);
      const selectProject = store.withSelector(state => state.project);
      const selectIsLoading = store.withSelector(state => state.isLoading);

      // Initial values
      expect(selectUser()).toBe(null);
      expect(selectProject()).toBe(null);
      expect(selectIsLoading()).toBe(true); // Should be loading during request

      // Same selector calls should return same reference
      expect(selectUser()).toBe(selectUser());
      expect(selectProject()).toBe(selectProject());
    });

    test('complex session context updates maintain referential stability', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      mockChannel.push = (_event: string, _payload: unknown) => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => {
                callback(
                  createMockSessionContext({
                    user: {
                      id: '111e8400-e29b-41d4-a716-446655440000',
                      first_name: 'Complex',
                      last_name: 'User',
                      email: 'complex@example.com',
                      email_confirmed: true,
                      inserted_at: '2024-02-01T12:00:00Z',
                    },
                  })
                );
              }, 0);
            }
            return {
              receive: () => {
                return { receive: () => ({ receive: () => ({}) }) };
              },
            };
          },
        };
      };

      store._connectChannel(mockProvider);
      await store.requestSessionContext();

      const state = store.getSnapshot();
      expect(state.user?.first_name).toBe('Complex');
      expect(state.user?.email).toBe('complex@example.com');

      // Create selector
      const selectUser = store.withSelector(state => state.user);
      const user1 = selectUser();

      // Unrelated state change should not affect user reference
      store.setLoading(true);
      const user2 = selectUser();

      expect(user1).toBe(user2); // Reference should remain stable
    });
  });
});
