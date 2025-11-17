/**
 * Tests for createSessionContextStore - Validation & Edge Cases
 *
 * This test suite covers:
 * - Data validation (invalid user IDs, emails, config)
 * - Edge case handling (multiple subscribers, rapid updates, null handling)
 * - Channel cleanup and error scenarios
 */

import { describe, expect, test } from 'vitest';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';

import { invalidSessionContextData } from '../__helpers__/sessionContextFactory';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../mocks/phoenixChannel';

describe('createSessionContextStore - Validation & Edge Cases', () => {
  describe('validation', () => {
    test('handles invalid user ID gracefully', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      mockChannel.push = (_event: string, _payload: unknown) => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => {
                callback(invalidSessionContextData.invalidUserId);
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
      expect(state.error?.includes('Invalid session context data')).toBe(true);
    });

    test('handles invalid user email gracefully', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      mockChannel.push = (_event: string, _payload: unknown) => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => {
                callback(invalidSessionContextData.invalidUserEmail);
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
      expect(state.error?.includes('Invalid session context data')).toBe(true);
    });

    test('handles missing config gracefully', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      mockChannel.push = (_event: string, _payload: unknown) => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => {
                callback(invalidSessionContextData.missingConfig);
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
      expect(state.error?.includes('Invalid session context data')).toBe(true);
    });

    test('handles invalid config type gracefully', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      mockChannel.push = (_event: string, _payload: unknown) => {
        return {
          receive: (status: string, callback: (response?: unknown) => void) => {
            if (status === 'ok') {
              setTimeout(() => {
                callback(invalidSessionContextData.invalidConfigType);
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
      expect(state.error?.includes('Invalid session context data')).toBe(true);
    });
  });

  describe('edge cases', () => {
    test('handles multiple subscribers correctly', () => {
      const store = createSessionContextStore();

      let listener1Count = 0;
      let listener2Count = 0;
      let listener3Count = 0;

      const unsubscribe1 = store.subscribe(() => {
        listener1Count++;
      });
      const unsubscribe2 = store.subscribe(() => {
        listener2Count++;
      });
      const unsubscribe3 = store.subscribe(() => {
        listener3Count++;
      });

      // Trigger change
      store.setLoading(true);

      expect(listener1Count).toBe(1);
      expect(listener2Count).toBe(1);
      expect(listener3Count).toBe(1);

      // Unsubscribe middle listener
      unsubscribe2();

      // Trigger another change
      store.setError('test');

      expect(listener1Count).toBe(2);
      expect(listener2Count).toBe(1); // Unsubscribed listener should not be called
      expect(listener3Count).toBe(2);

      // Cleanup
      unsubscribe1();
      unsubscribe3();
    });

    test('maintains state consistency during rapid updates', () => {
      const store = createSessionContextStore();
      let notificationCount = 0;

      store.subscribe(() => {
        notificationCount++;
      });

      // Perform rapid state updates
      store.setLoading(true);
      store.setError('error 1');
      store.clearError();
      store.setLoading(false);
      store.setError('error 2');
      store.clearError();

      // Each operation should trigger exactly one notification
      expect(notificationCount).toBe(6);

      // Final state should be consistent
      const finalState = store.getSnapshot();
      expect(finalState.isLoading).toBe(false);
      expect(finalState.error).toBe(null);
    });

    test('handles null and undefined channel provider gracefully', async () => {
      const store = createSessionContextStore();

      // Test with null provider
      try {
        store._connectChannel(null as any);
        throw new Error('Should have thrown error for null provider');
      } catch (error) {
        expect(error instanceof TypeError).toBe(true);
      }

      // Test with undefined provider
      try {
        store._connectChannel(undefined as any);
        throw new Error('Should have thrown error for undefined provider');
      } catch (error) {
        expect(error instanceof TypeError).toBe(true);
      }

      // Test requestSessionContext without any channel connection
      await store.requestSessionContext();

      const state = store.getSnapshot();
      expect(state.error?.includes('No connection available') ?? false).toBe(
        true
      );
    });
  });
});
