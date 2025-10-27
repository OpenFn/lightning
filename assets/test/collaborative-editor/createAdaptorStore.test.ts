/**
 * Tests for createAdaptorStore
 *
 * This test suite covers all aspects of the AdaptorStore:
 * - Core store interface (subscribe/getSnapshot)
 * - State management commands (setLoading, setError, etc.)
 * - Channel integration and message handling
 * - Query helpers (findAdaptorByName, getLatestVersion, etc.)
 * - Error handling and validation
 */

/**
 * Test Fixtures
 *
 * This file uses Vitest 3.x fixtures for cleaner test setup and automatic cleanup.
 *
 * Available fixtures:
 * - store: AdaptorStore instance (auto cleanup)
 * - mockChannel: Mock Phoenix channel
 * - mockProvider: Mock Phoenix channel provider (depends on mockChannel)
 * - connectedStore: Store with channel connected (auto cleanup)
 *
 * Usage:
 * adaptorTest("test name", async ({ connectedStore }) => {
 *   const { store, provider } = connectedStore;
 *   // test logic - cleanup automatic
 * });
 */

import { describe, test, expect } from 'vitest';

import { createAdaptorStore } from '../../js/collaborative-editor/stores/createAdaptorStore';
import type { AdaptorStoreInstance } from '../../js/collaborative-editor/stores/createAdaptorStore';

import {
  mockAdaptorsList,
  mockAdaptor,
  invalidAdaptorData,
} from './fixtures/adaptorData.js';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  waitForCondition,
} from './mocks/phoenixChannel.js';
import {
  createMockChannelPushOk,
  createMockChannelPushError,
} from './__helpers__/channelMocks';
import type {
  MockPhoenixChannel,
  MockPhoenixChannelProvider,
} from './mocks/phoenixChannel.js';

// Define fixture types
interface AdaptorTestFixtures {
  store: AdaptorStoreInstance;
  mockChannel: MockPhoenixChannel;
  mockProvider: MockPhoenixChannelProvider;
  connectedStore: {
    store: AdaptorStoreInstance;
    provider: MockPhoenixChannelProvider;
    cleanup: () => void;
  };
}

// Vitest 3.x fixtures for cleaner test setup and automatic cleanup
const adaptorTest = test.extend<AdaptorTestFixtures>({
  store: async ({}, use) => {
    const store = createAdaptorStore();
    await use(store);
    // Automatic cleanup - store doesn't need explicit cleanup
  },

  mockChannel: async ({}, use) => {
    const channel = createMockPhoenixChannel();
    await use(channel);
    // Channel cleanup happens automatically
  },

  mockProvider: async ({ mockChannel }, use) => {
    const provider = createMockPhoenixChannelProvider(mockChannel);
    await use(provider);
  },

  connectedStore: async ({ store, mockProvider }, use) => {
    // Setup: connect channel to store
    const cleanup = store._connectChannel(mockProvider as any);

    await use({ store, provider: mockProvider, cleanup });

    // Automatic cleanup
    cleanup();
  },
});

// Helper to create expected sorted adaptors (alphabetically by name, versions descending)
function getSortedAdaptors(adaptors: any[]) {
  return [...adaptors]
    .sort((a, b) => a.name.localeCompare(b.name))
    .map(adaptor => ({
      ...adaptor,
      versions: [...adaptor.versions].sort((a, b) =>
        b.version.localeCompare(a.version)
      ),
    }));
}

describe('createAdaptorStore', () => {
  describe('initialization', () => {
    test('getSnapshot returns initial state', () => {
      const store = createAdaptorStore();
      const initialState = store.getSnapshot();

      expect(initialState.adaptors).toEqual([]);
      expect(initialState.isLoading).toBe(false);
      expect(initialState.error).toBe(null);
      expect(initialState.lastUpdated).toBe(null);
    });
  });

  describe('subscriptions', () => {
    test('subscribe/unsubscribe functionality works correctly', () => {
      const store = createAdaptorStore();
      let callCount = 0;

      const listener = () => {
        callCount++;
      };

      // Subscribe to changes
      const unsubscribe = store.subscribe(listener);

      // Trigger a state change
      store.setLoading(true);

      expect(callCount).toBe(1);

      // Unsubscribe and trigger change
      unsubscribe();
      store.clearError();

      // Listener should not be called after unsubscribe
      expect(callCount).toBe(1);
    });

    test('withSelector creates memoized selector with referential stability', () => {
      const store = createAdaptorStore();

      const selectAdaptors = store.withSelector(state => state.adaptors);
      const selectIsLoading = store.withSelector(state => state.isLoading);

      // Initial calls
      const adaptors1 = selectAdaptors();
      const loading1 = selectIsLoading();

      // Change unrelated state - adaptors selector should return same reference
      store.setLoading(true);
      const adaptors3 = selectAdaptors();
      const loading3 = selectIsLoading();

      // Unrelated state change should not affect memoized selector
      expect(adaptors1).toBe(adaptors3);
      // Related state change should return new value
      expect(loading1).not.toBe(loading3);
    });

    test('handles multiple subscribers correctly', () => {
      const store = createAdaptorStore();

      let listener1Count = 0;
      let listener2Count = 0;

      const unsubscribe1 = store.subscribe(() => {
        listener1Count++;
      });
      const unsubscribe2 = store.subscribe(() => {
        listener2Count++;
      });

      // Trigger change
      store.setLoading(true);

      expect(listener1Count).toBe(1);
      expect(listener2Count).toBe(1);

      // Unsubscribe middle listener
      unsubscribe2();

      // Trigger another change
      store.setError('test');

      // Unsubscribed listener should not be called
      expect(listener2Count).toBe(1);

      // Cleanup
      unsubscribe1();
    });
  });

  describe('state management', () => {
    test('handles state transitions for loading, error, and data correctly', () => {
      const store = createAdaptorStore();
      let notificationCount = 0;

      store.subscribe(() => {
        notificationCount++;
      });

      // Test loading state transitions
      store.setLoading(true);
      expect(store.getSnapshot().isLoading).toBe(true);
      expect(notificationCount).toBe(1);

      store.setLoading(false);
      expect(store.getSnapshot().isLoading).toBe(false);
      expect(notificationCount).toBe(2);

      // Test error state transitions
      store.setLoading(true);
      const errorMessage = 'Test error message';
      store.setError(errorMessage);
      let state = store.getSnapshot();
      expect(state.error).toBe(errorMessage);
      expect(state.isLoading).toBe(false); // Setting error clears loading

      store.clearError();
      expect(store.getSnapshot().error).toBeNull();

      // Test adaptors state updates
      const timestamp = Date.now();
      store.setAdaptors(mockAdaptorsList);
      state = store.getSnapshot();
      expect(state.adaptors).toEqual(mockAdaptorsList);
      expect(state.error).toBeNull();
      expect(state.lastUpdated).toBeGreaterThanOrEqual(timestamp);

      // Test rapid state updates maintain consistency
      store.setLoading(true);
      store.setError('error 1');
      store.clearError();
      store.setAdaptors(mockAdaptorsList);
      store.setLoading(false);
      store.setError('error 2');
      store.clearError();

      // Final state should be consistent
      const finalState = store.getSnapshot();
      expect(finalState.adaptors).toEqual(mockAdaptorsList);
      expect(finalState.isLoading).toBe(false);
      expect(finalState.error).toBeNull();
      expect(finalState.lastUpdated).toBeGreaterThan(0);
    });
  });

  describe('Phoenix channel integration', () => {
    describe('requestAdaptors', () => {
      adaptorTest(
        'processes valid and invalid data via channel',
        async ({ mockChannel, mockProvider }) => {
          // Test successful response with valid data
          const store1 = createAdaptorStore();
          mockChannel.push = createMockChannelPushOk({
            adaptors: mockAdaptorsList,
          });
          store1._connectChannel(mockProvider as any);
          await store1.requestAdaptors();

          let state = store1.getSnapshot();
          const expectedSortedAdaptors = getSortedAdaptors(mockAdaptorsList);

          expect(state.adaptors).toEqual(expectedSortedAdaptors);
          expect(state.isLoading).toBe(false);
          expect(state.error).toBeNull();
          expect(state.lastUpdated).toBeGreaterThan(0);
          expect(state.adaptors).toHaveLength(mockAdaptorsList.length);

          // Test invalid data handling with fresh store
          const store2 = createAdaptorStore();
          mockChannel.push = createMockChannelPushOk({
            adaptors: [invalidAdaptorData.missingName],
          });
          store2._connectChannel(mockProvider as any);
          await store2.requestAdaptors();

          state = store2.getSnapshot();
          expect(state.adaptors).toHaveLength(0);
          expect(state.isLoading).toBe(false);
          expect(state.error).toContain('Invalid adaptors data');
        }
      );

      adaptorTest(
        'handles error response and no connection',
        async ({ store, mockChannel, mockProvider }) => {
          // Test error response
          mockChannel.push = createMockChannelPushError(
            'Server error',
            'server_error'
          );
          store._connectChannel(mockProvider as any);
          await store.requestAdaptors();

          let state = store.getSnapshot();
          expect(state.adaptors).toHaveLength(0);
          expect(state.error).toContain('Failed to request adaptors');
          expect(state.isLoading).toBe(false);

          // Test no channel connection
          const storeWithoutChannel = createAdaptorStore();
          await storeWithoutChannel.requestAdaptors();

          state = storeWithoutChannel.getSnapshot();
          expect(state.error).toContain('No connection available');
          expect(state.isLoading).toBe(false);
        }
      );
    });

    describe('channel connection and events', () => {
      adaptorTest(
        'connects channel, loads adaptors, and processes real-time updates',
        async ({ store, mockChannel, mockProvider }) => {
          // Setup mock to return adaptors on initial request
          mockChannel.push = createMockChannelPushOk({
            adaptors: mockAdaptorsList,
          });

          // Connect to channel
          const cleanup = store._connectChannel(mockProvider as any);

          // Wait for initial adaptors to be loaded
          await waitForCondition(() => store.getSnapshot().adaptors.length > 0);

          // Verify initial load with sorting
          let state = store.getSnapshot();
          const expectedSortedAdaptors = getSortedAdaptors(mockAdaptorsList);
          expect(state.adaptors).toEqual(expectedSortedAdaptors);

          // Test real-time updates via adaptors_updated event
          const updatedAdaptors = [mockAdaptor];
          const mockChannelWithTest = mockChannel as typeof mockChannel & {
            _test: { emit: (event: string, message: unknown) => void };
          };
          mockChannelWithTest._test.emit('adaptors_updated', updatedAdaptors);

          // Wait for the update to be processed
          await waitForCondition(
            () => store.getSnapshot().adaptors.length === 1
          );

          state = store.getSnapshot();
          const expectedUpdatedAdaptors = getSortedAdaptors(updatedAdaptors);
          expect(state.adaptors).toEqual(expectedUpdatedAdaptors);

          // Cleanup
          cleanup();
        }
      );
    });

    describe('error handling', () => {
      test('handles invalid channel provider', async () => {
        const store = createAdaptorStore();

        // Test with null provider
        expect(() => store._connectChannel(null as any)).toThrow(TypeError);

        // Test with undefined provider
        expect(() => store._connectChannel(undefined as any)).toThrow(
          TypeError
        );
      });
    });
  });

  describe('query helpers', () => {
    test('findAdaptorByName returns correct adaptor', () => {
      const store = createAdaptorStore();
      store.setAdaptors(mockAdaptorsList);

      const foundAdaptor = store.findAdaptorByName('@openfn/language-http');
      expect(foundAdaptor).toEqual(mockAdaptor);

      const notFound = store.findAdaptorByName('@openfn/language-nonexistent');
      expect(notFound).toBeNull();
    });

    test('getLatestVersion returns correct version', () => {
      const store = createAdaptorStore();
      store.setAdaptors(mockAdaptorsList);

      const latestVersion = store.getLatestVersion('@openfn/language-http');
      expect(latestVersion).toBe('2.1.0');

      const notFound = store.getLatestVersion('@openfn/language-nonexistent');
      expect(notFound).toBeNull();
    });

    test('getVersions returns correct versions array', () => {
      const store = createAdaptorStore();
      store.setAdaptors(mockAdaptorsList);

      const versions = store.getVersions('@openfn/language-http');
      expect(versions).toEqual(mockAdaptor.versions);

      const notFound = store.getVersions('@openfn/language-nonexistent');
      expect(notFound).toHaveLength(0);
    });
  });
});
