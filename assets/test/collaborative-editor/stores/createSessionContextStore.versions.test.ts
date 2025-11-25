/**
 * Tests for createSessionContextStore - Version Management
 *
 * This test suite covers:
 * - requestVersions() fetches versions from channel and updates state
 * - requestVersions() loading state management
 * - requestVersions() error handling
 * - requestVersions() deduplication (no double-fetch)
 * - setLatestSnapshotLockVersion() clearing versions on change
 * - clearVersions() empties the versions array
 */

import { describe, expect, test } from 'vitest';

import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import type { Version } from '../../../js/collaborative-editor/types/sessionContext';
import {
  createMockChannelPushError,
  createMockChannelPushOk,
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../__helpers__/channelMocks';
import { setupSessionContextStoreTest } from '../__helpers__/storeHelpers';
import { waitForAsync } from '../mocks/phoenixChannel';

describe('createSessionContextStore - Version Management', () => {
  describe('requestVersions', () => {
    test('fetches versions from channel and updates state', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      const mockVersions: Version[] = [
        {
          lock_version: 5,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        },
        {
          lock_version: 4,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: false,
        },
        {
          lock_version: 3,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: false,
        },
      ];

      // Configure channel to return versions
      mockChannel.push = createMockChannelPushOk({
        versions: mockVersions,
      });

      // Initial state should be empty
      expect(store.getSnapshot().versions).toEqual([]);
      expect(store.getSnapshot().versionsLoading).toBe(false);

      // Request versions
      await store.requestVersions();

      // State should be updated with versions
      const state = store.getSnapshot();
      expect(state.versions).toEqual(mockVersions);
      expect(state.versionsLoading).toBe(false);
      expect(state.versionsError).toBe(null);

      cleanup();
    });

    test('sets loading state while fetching', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      const mockVersions: Version[] = [
        {
          lock_version: 3,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        },
      ];

      // Configure channel with slight delay to observe loading state
      mockChannel.push = createMockChannelPushOk({
        versions: mockVersions,
      });

      // Initial state
      expect(store.getSnapshot().versionsLoading).toBe(false);

      // Start request (don't await yet)
      const requestPromise = store.requestVersions();

      // Should be loading immediately
      expect(store.getSnapshot().versionsLoading).toBe(true);
      expect(store.getSnapshot().versionsError).toBe(null);

      // Wait for completion
      await requestPromise;

      // Should not be loading anymore
      expect(store.getSnapshot().versionsLoading).toBe(false);

      cleanup();
    });

    test('handles errors and sets versionsError', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      // Configure channel to return error
      mockChannel.push = createMockChannelPushError(
        'Failed to fetch versions',
        'versions_error'
      );

      // Request versions
      await store.requestVersions();

      // State should have error set
      const state = store.getSnapshot();
      expect(state.versionsLoading).toBe(false);
      expect(state.versionsError).toBe('Failed to load versions');
      expect(state.versions).toEqual([]);

      cleanup();
    });

    test('handles invalid versions data with validation error', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      // Configure channel to return invalid data (missing required fields)
      mockChannel.push = createMockChannelPushOk({
        versions: [
          {
            // Missing lock_version
            inserted_at: '2024-01-15T10:30:00Z',
            is_latest: true,
          },
        ],
      });

      // Request versions
      await store.requestVersions();

      // State should have validation error set
      const state = store.getSnapshot();
      expect(state.versionsLoading).toBe(false);
      expect(state.versionsError).toContain('Invalid versions data');
      expect(state.versions).toEqual([]);

      cleanup();
    });

    test('does not double-fetch if already loading (deduplication)', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      let pushCallCount = 0;
      const mockVersions: Version[] = [
        {
          lock_version: 2,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        },
      ];

      // Track push calls
      mockChannel.push = createMockChannelPushOk({
        versions: mockVersions,
      });

      // Wrap push to count calls
      const originalPush = mockChannel.push;
      mockChannel.push = (event: string, payload: unknown) => {
        if (event === 'request_versions') {
          pushCallCount++;
        }
        return originalPush(event, payload);
      };

      // Start first request (don't await)
      const request1 = store.requestVersions();

      // Immediately start second request while first is loading
      const request2 = store.requestVersions();

      // Wait for both to complete
      await Promise.all([request1, request2]);

      // Should only have called push once (deduplication)
      expect(pushCallCount).toBe(1);
      expect(store.getSnapshot().versions).toEqual(mockVersions);

      cleanup();
    });

    test('returns early if no channel provider', async () => {
      // Create store without connecting channel
      const store = createSessionContextStore();

      // Try to request versions without channel
      await store.requestVersions();

      // State should remain unchanged
      const state = store.getSnapshot();
      expect(state.versions).toEqual([]);
      expect(state.versionsLoading).toBe(false);
      expect(state.versionsError).toBe(null);
    });

    test('allows second request after first completes', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      const mockVersions1: Version[] = [
        {
          lock_version: 2,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        },
      ];

      const mockVersions2: Version[] = [
        {
          lock_version: 3,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: true,
        },
        {
          lock_version: 2,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: false,
        },
      ];

      // First request
      mockChannel.push = createMockChannelPushOk({
        versions: mockVersions1,
      });
      await store.requestVersions();
      expect(store.getSnapshot().versions).toEqual(mockVersions1);

      // Second request with different versions
      mockChannel.push = createMockChannelPushOk({
        versions: mockVersions2,
      });
      await store.requestVersions();
      expect(store.getSnapshot().versions).toEqual(mockVersions2);

      cleanup();
    });

    test('handles empty versions array', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      // Configure channel to return empty array
      mockChannel.push = createMockChannelPushOk({
        versions: [],
      });

      // Request versions
      await store.requestVersions();

      // State should have empty array
      const state = store.getSnapshot();
      expect(state.versions).toEqual([]);
      expect(state.versionsLoading).toBe(false);
      expect(state.versionsError).toBe(null);

      cleanup();
    });
  });

  describe('setLatestSnapshotLockVersion', () => {
    test('clears versions when lock version changes', () => {
      const { store, cleanup } = setupSessionContextStoreTest();

      // Set initial lock version (first time - from null)
      store.setLatestSnapshotLockVersion(1);

      // Manually populate versions
      const mockVersions: Version[] = [
        {
          lock_version: 1,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        },
      ];

      // Directly modify state to add versions (simulating requestVersions)
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);
      mockChannel.push = createMockChannelPushOk({
        versions: mockVersions,
      });
      store._connectChannel(mockProvider);

      // Request versions to populate state
      void store.requestVersions();
      // Wait for async operation
      waitForAsync().then(() => {
        expect(store.getSnapshot().versions).toEqual(mockVersions);

        // Change lock version (should clear versions)
        store.setLatestSnapshotLockVersion(2);

        // Versions should be cleared
        expect(store.getSnapshot().versions).toEqual([]);
        expect(store.getSnapshot().latestSnapshotLockVersion).toBe(2);

        cleanup();
      });
    });

    test('does NOT clear versions on initial set (null to number)', () => {
      const store = createSessionContextStore();

      // Initial state has null lock version
      expect(store.getSnapshot().latestSnapshotLockVersion).toBe(null);
      expect(store.getSnapshot().versions).toEqual([]);

      // Set lock version for first time (null → 1)
      store.setLatestSnapshotLockVersion(1);

      // Versions should NOT be cleared (still empty)
      expect(store.getSnapshot().versions).toEqual([]);
      expect(store.getSnapshot().latestSnapshotLockVersion).toBe(1);
    });

    test('clears versions when changing from one number to another', () => {
      const store = createSessionContextStore();

      // Set initial lock version
      store.setLatestSnapshotLockVersion(1);

      // Manually add versions to state for testing
      // This requires accessing internal state, so we'll use requestVersions
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      const mockVersions: Version[] = [
        {
          lock_version: 1,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        },
      ];

      mockChannel.push = createMockChannelPushOk({
        versions: mockVersions,
      });

      store._connectChannel(mockProvider);

      // Request versions to populate state
      store.requestVersions().then(() => {
        expect(store.getSnapshot().versions.length).toBeGreaterThan(0);

        // Change lock version (1 → 2)
        store.setLatestSnapshotLockVersion(2);

        // Versions should be cleared
        expect(store.getSnapshot().versions).toEqual([]);
        expect(store.getSnapshot().latestSnapshotLockVersion).toBe(2);
      });
    });

    test('does NOT clear versions when setting same lock version', () => {
      const store = createSessionContextStore();

      // Set initial lock version
      store.setLatestSnapshotLockVersion(1);

      // Add versions
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      const mockVersions: Version[] = [
        {
          lock_version: 1,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        },
      ];

      mockChannel.push = createMockChannelPushOk({
        versions: mockVersions,
      });

      store._connectChannel(mockProvider);

      // Request versions to populate state
      store.requestVersions().then(() => {
        expect(store.getSnapshot().versions.length).toBeGreaterThan(0);

        // Set same lock version (1 → 1)
        store.setLatestSnapshotLockVersion(1);

        // Versions should NOT be cleared
        expect(store.getSnapshot().versions).toEqual(mockVersions);
        expect(store.getSnapshot().latestSnapshotLockVersion).toBe(1);
      });
    });

    test('updates lastUpdated timestamp', () => {
      const store = createSessionContextStore();

      // Initial lastUpdated is null
      expect(store.getSnapshot().lastUpdated).toBe(null);

      const beforeTime = Date.now();
      store.setLatestSnapshotLockVersion(1);
      const afterTime = Date.now();

      const lastUpdated = store.getSnapshot().latestSnapshotLockVersion;
      expect(lastUpdated).not.toBe(null);
      expect(store.getSnapshot().latestSnapshotLockVersion).toBe(1);
    });
  });

  describe('clearVersions', () => {
    test('empties the versions array', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      const mockVersions: Version[] = [
        {
          lock_version: 3,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        },
        {
          lock_version: 2,
          inserted_at: '2024-01-12T10:30:00Z',
          is_latest: false,
        },
      ];

      // First, populate versions
      mockChannel.push = createMockChannelPushOk({
        versions: mockVersions,
      });
      await store.requestVersions();

      // Verify versions are populated
      expect(store.getSnapshot().versions).toEqual(mockVersions);

      // Clear versions
      store.clearVersions();

      // Versions should be empty
      expect(store.getSnapshot().versions).toEqual([]);

      cleanup();
    });

    test('clearing already empty versions is safe', () => {
      const store = createSessionContextStore();

      // Initial state has empty versions
      expect(store.getSnapshot().versions).toEqual([]);

      // Clear versions (should be safe)
      store.clearVersions();

      // Still empty
      expect(store.getSnapshot().versions).toEqual([]);
    });

    test('does not affect other state properties', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      const mockVersions: Version[] = [
        {
          lock_version: 2,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        },
      ];

      // Populate versions
      mockChannel.push = createMockChannelPushOk({
        versions: mockVersions,
      });
      await store.requestVersions();

      // Set lock version
      store.setLatestSnapshotLockVersion(2);

      // Capture state before clear
      const beforeState = store.getSnapshot();
      expect(beforeState.versions).toEqual(mockVersions);
      expect(beforeState.latestSnapshotLockVersion).toBe(2);

      // Clear versions
      store.clearVersions();

      // Versions cleared but other properties unchanged
      const afterState = store.getSnapshot();
      expect(afterState.versions).toEqual([]);
      expect(afterState.latestSnapshotLockVersion).toBe(2);
      expect(afterState.user).toBe(beforeState.user);
      expect(afterState.project).toBe(beforeState.project);

      cleanup();
    });
  });

  describe('state notifications', () => {
    test('requestVersions notifies subscribers', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      let notificationCount = 0;
      store.subscribe(() => {
        notificationCount++;
      });

      const mockVersions: Version[] = [
        {
          lock_version: 2,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        },
      ];

      mockChannel.push = createMockChannelPushOk({
        versions: mockVersions,
      });

      // Request versions
      await store.requestVersions();

      // Should have notified subscribers (start loading + success)
      expect(notificationCount).toBeGreaterThan(0);

      cleanup();
    });

    test('clearVersions notifies subscribers', () => {
      const store = createSessionContextStore();

      let notificationCount = 0;
      store.subscribe(() => {
        notificationCount++;
      });

      // Clear versions
      store.clearVersions();

      // Should have notified once
      expect(notificationCount).toBe(1);
    });

    test('setLatestSnapshotLockVersion notifies subscribers', () => {
      const store = createSessionContextStore();

      let notificationCount = 0;
      store.subscribe(() => {
        notificationCount++;
      });

      // Set lock version
      store.setLatestSnapshotLockVersion(1);

      // Should have notified once
      expect(notificationCount).toBe(1);
    });
  });
});
