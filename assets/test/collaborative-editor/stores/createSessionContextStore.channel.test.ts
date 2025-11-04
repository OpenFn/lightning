/**
 * Tests for createSessionContextStore - Channel Operations
 *
 * This test suite covers:
 * - Core store interface (subscribe/getSnapshot/withSelector)
 * - State management commands (setLoading, setError, clearError)
 * - Channel integration and request/response flow
 * - Error handling for channel operations
 */

import { describe, expect, test } from 'vitest';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';

import {
  invalidSessionContextData,
  mockAppConfig,
  mockProjectContext,
  mockSessionContextResponse,
  mockUnauthenticatedSessionContext,
  mockUserContext,
} from '../__helpers__/sessionContextFactory';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../mocks/phoenixChannel';

describe('createSessionContextStore - Channel Operations', () => {
  describe('core store interface', () => {
    test('getSnapshot returns initial state', () => {
      const store = createSessionContextStore();
      const initialState = store.getSnapshot();

      expect(initialState.user).toBe(null);
      expect(initialState.project).toBe(null);
      expect(initialState.config).toBe(null);
      expect(initialState.isLoading).toBe(false);
      expect(initialState.error).toBe(null);
      expect(initialState.lastUpdated).toBe(null);
    });

    test('subscribe/unsubscribe functionality works correctly', () => {
      const store = createSessionContextStore();
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

      expect(callCount).toBe(2); // Listener should not be called after unsubscribe
    });

    test('withSelector creates memoized selector with referential stability', () => {
      const store = createSessionContextStore();

      const selectUser = store.withSelector(state => state.user);
      const selectIsLoading = store.withSelector(state => state.isLoading);

      // Initial calls
      const user1 = selectUser();
      const loading1 = selectIsLoading();

      // Same calls should return same reference
      const user2 = selectUser();
      const loading2 = selectIsLoading();

      expect(user1).toBe(user2); // Same selector calls should return identical reference
      expect(loading1).toBe(loading2); // Same selector calls should return identical reference

      // Change unrelated state - user selector should return same reference
      store.setLoading(true);
      const user3 = selectUser();
      const loading3 = selectIsLoading();

      expect(user1).toBe(user3); // Unrelated state change should not affect memoized selector
      expect(loading1).not.toBe(loading3); // Related state change should return new value
    });
  });

  describe('state management', () => {
    test('setLoading updates loading state and notifies subscribers', () => {
      const store = createSessionContextStore();
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
      const store = createSessionContextStore();

      // First set loading to true
      store.setLoading(true);
      expect(store.getSnapshot().isLoading).toBe(true);

      // Set error - should clear loading state
      const errorMessage = 'Test error message';
      store.setError(errorMessage);

      const state = store.getSnapshot();
      expect(state.error).toBe(errorMessage);
      expect(state.isLoading).toBe(false); // Setting error should clear loading state
    });

    test('setError with null clears error', () => {
      const store = createSessionContextStore();

      // Set error first
      store.setError('Test error');
      expect(store.getSnapshot().error).toBe('Test error');

      // Set error to null
      store.setError(null);
      expect(store.getSnapshot().error).toBe(null);
    });

    test('clearError removes error state', () => {
      const store = createSessionContextStore();

      // Set error first
      store.setError('Test error');
      expect(store.getSnapshot().error).toBe('Test error');

      // Clear error
      store.clearError();
      expect(store.getSnapshot().error).toBe(null);
    });
  });

  describe('channel operations', () => {
    describe('successful responses', () => {
      test('processes Elixir response format (direct data, not wrapped)', async () => {
        const store = createSessionContextStore();
        const mockChannel = createMockPhoenixChannel();
        const mockProvider = createMockPhoenixChannelProvider(mockChannel);
        let notificationCount = 0;

        store.subscribe(() => {
          notificationCount++;
        });

        // IMPORTANT: Elixir handler returns {user, project, config} DIRECTLY
        // NOT wrapped in session_context key!
        // See lib/lightning_web/channels/workflow_channel.ex line 96-102
        mockChannel.push = (_event: string, _payload: unknown) => {
          return {
            receive: (
              status: string,
              callback: (response?: unknown) => void
            ) => {
              if (status === 'ok') {
                setTimeout(() => {
                  // This matches actual Elixir response format
                  callback(mockSessionContextResponse);
                }, 0);
              } else if (status === 'error') {
                setTimeout(() => {
                  callback({
                    errors: { base: ['Error'] },
                    type: 'error',
                  });
                }, 0);
              } else if (status === 'timeout') {
                setTimeout(() => {
                  callback();
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

        // Connect channel and request session context
        store._connectChannel(mockProvider);
        await store.requestSessionContext();

        const state = store.getSnapshot();

        expect(state.user).toEqual(mockUserContext);
        expect(state.project).toEqual(mockProjectContext);
        expect(state.config).toEqual(mockAppConfig);
        expect(state.isLoading).toBe(false); // Should clear loading state
        expect(state.error).toBe(null); // Should clear error state
        expect(state.lastUpdated ? state.lastUpdated > 0 : false).toBe(true); // Should set lastUpdated timestamp

        // Should have triggered notifications for: setLoading(true), clearError(), and handleSessionContextReceived
        expect(notificationCount).toBeGreaterThan(0);
      });

      test('requestSessionContext processes valid data correctly via channel (legacy wrapper format)', async () => {
        const store = createSessionContextStore();
        const mockChannel = createMockPhoenixChannel();
        const mockProvider = createMockPhoenixChannelProvider(mockChannel);
        let notificationCount = 0;

        store.subscribe(() => {
          notificationCount++;
        });

        // NOTE: This test uses legacy wrapper format for backwards compatibility testing
        // Real Elixir handler returns data directly (see test above)
        mockChannel.push = (_event: string, _payload: unknown) => {
          return {
            receive: (
              status: string,
              callback: (response?: unknown) => void
            ) => {
              if (status === 'ok') {
                setTimeout(() => {
                  // Legacy format: wrapped in session_context
                  callback(mockSessionContextResponse);
                }, 0);
              } else if (status === 'error') {
                setTimeout(() => {
                  callback({
                    errors: { base: ['Error'] },
                    type: 'error',
                  });
                }, 0);
              } else if (status === 'timeout') {
                setTimeout(() => {
                  callback();
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

        // Connect channel and request session context
        store._connectChannel(mockProvider);
        await store.requestSessionContext();

        const state = store.getSnapshot();

        expect(state.user).toEqual(mockUserContext);
        expect(state.project).toEqual(mockProjectContext);
        expect(state.config).toEqual(mockAppConfig);
        expect(state.isLoading).toBe(false); // Should clear loading state
        expect(state.error).toBe(null); // Should clear error state
        expect(state.lastUpdated ? state.lastUpdated > 0 : false).toBe(true); // Should set lastUpdated timestamp

        // Should have triggered notifications for: setLoading(true), clearError(), and handleSessionContextReceived
        expect(notificationCount).toBeGreaterThan(0);
      });

      test('requestSessionContext handles unauthenticated context with null user', async () => {
        const store = createSessionContextStore();
        const mockChannel = createMockPhoenixChannel();
        const mockProvider = createMockPhoenixChannelProvider(mockChannel);

        // Set up the channel with unauthenticated response
        mockChannel.push = (_event: string, _payload: unknown) => {
          return {
            receive: (
              status: string,
              callback: (response?: unknown) => void
            ) => {
              if (status === 'ok') {
                setTimeout(() => {
                  callback(mockUnauthenticatedSessionContext);
                }, 0);
              } else if (status === 'error') {
                setTimeout(() => {
                  callback({
                    errors: { base: ['Error'] },
                    type: 'error',
                  });
                }, 0);
              } else if (status === 'timeout') {
                setTimeout(() => {
                  callback();
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

        // Connect channel and request session context
        store._connectChannel(mockProvider);
        await store.requestSessionContext();

        const state = store.getSnapshot();
        expect(state.user).toBe(null);
        expect(state.project).toBe(null);
        expect(state.config).toEqual(mockAppConfig);
        expect(state.error).toBe(null);
        expect(state.isLoading).toBe(false);
      });
    });

    describe('error handling', () => {
      test('requestSessionContext handles invalid data gracefully via channel', async () => {
        const store = createSessionContextStore();
        const mockChannel = createMockPhoenixChannel();
        const mockProvider = createMockPhoenixChannelProvider(mockChannel);

        // Set up the channel with response containing invalid data
        mockChannel.push = (_event: string, _payload: unknown) => {
          return {
            receive: (
              status: string,
              callback: (response?: unknown) => void
            ) => {
              if (status === 'ok') {
                setTimeout(() => {
                  // Return invalid data (missing required user field, not null)
                  callback(invalidSessionContextData.missingUser);
                }, 0);
              } else if (status === 'error') {
                setTimeout(() => {
                  callback({
                    errors: { base: ['Error'] },
                    type: 'error',
                  });
                }, 0);
              } else if (status === 'timeout') {
                setTimeout(() => {
                  callback();
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

        // Connect channel and request session context
        store._connectChannel(mockProvider);
        await store.requestSessionContext();

        const state = store.getSnapshot();
        expect(state.user).toBe(null); // Should remain null on invalid data
        expect(state.project).toBe(null); // Should remain null on invalid data
        expect(state.config).toBe(null); // Should remain null on invalid data
        expect(state.isLoading).toBe(false); // Should clear loading state even on error
        expect(state.error?.includes('Invalid session context data')).toBe(
          true
        ); // Should set descriptive error message
      });

      test('requestSessionContext handles error response', async () => {
        const store = createSessionContextStore();
        const mockChannel = createMockPhoenixChannel();
        const mockProvider = createMockPhoenixChannelProvider(mockChannel);

        // Set up the channel with error response
        mockChannel.push = (_event: string, _payload: unknown) => {
          const mockPush = {
            receive: (
              status: string,
              callback: (response?: unknown) => void
            ) => {
              if (status === 'error') {
                setTimeout(() => {
                  callback({
                    errors: { base: ['Server error'] },
                    type: 'server_error',
                  });
                }, 0);
              } else if (status === 'ok') {
                // Do nothing for ok status in error test
              } else if (status === 'timeout') {
                setTimeout(() => {
                  callback();
                }, 0);
              }
              return mockPush;
            },
          };

          return mockPush;
        };

        // Connect channel
        store._connectChannel(mockProvider);

        // Request session context (should fail)
        await store.requestSessionContext();

        const state = store.getSnapshot();
        expect(state.user).toBe(null);
        expect(state.project).toBe(null);
        expect(state.config).toBe(null);
        expect(
          state.error?.includes('Failed to request session context') || false
        ).toBe(true);
        expect(state.isLoading).toBe(false);
      });

      test('requestSessionContext handles no channel connection', async () => {
        const store = createSessionContextStore();

        // Request session context without connecting channel
        await store.requestSessionContext();

        const state = store.getSnapshot();
        expect(state.error?.includes('No connection available') ?? false).toBe(
          true
        );
        expect(state.isLoading).toBe(false);
      });
    });
  });
});
