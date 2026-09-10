/**
 * Tests for createSessionContextStore - Version Management
 *
 * This test suite covers:
 * - requestReleases() fetches releases from channel and updates state
 * - requestReleases() loading state management
 * - requestReleases() error handling
 * - requestReleases() deduplication (no double-fetch)
 * - setLatestSnapshotLockVersion() clearing releases on change
 * - clearReleases() empties the releases array
 */

import { describe, expect, test, vi } from 'vitest';

import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import type { Release } from '../../../js/collaborative-editor/types/sessionContext';
import {
  createMockChannelPushError,
  createMockChannelPushOk,
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../__helpers__/channelMocks';
import { setupSessionContextStoreTest } from '../__helpers__/storeHelpers';
import { waitForAsync } from '../mocks/phoenixChannel';

// Builds a release entry matching the current channel payload shape. Tests
// override only the fields they care about; the round-trip through
// ReleaseSchema leaves these objects unchanged, so `toEqual` comparisons hold.
const makeVersion = (overrides: Partial<Release> = {}): Release => ({
  version_number: 1,
  kind: 'go_live',
  inserted_at: '2024-01-13T10:30:00Z',
  published_by: 'Test User',
  source_project: null,
  lock_version: 1,
  snapshot_id: 'snapshot-1',
  restored_from_version_number: null,
  is_latest: false,
  ...overrides,
});

describe('createSessionContextStore - Version Management', () => {
  describe('requestReleases', () => {
    test('asks for the publish trail by its own name', async () => {
      // `request_versions` is a different question with differently shaped rows
      // (every save, numbered by lock_version). Asking that one and reading the
      // reply as releases put snapshot numbers in the version dropdown.
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      mockChannel.push = createMockChannelPushOk({
        releases: [makeVersion()],
      });

      await store.requestReleases();

      const asked = vi
        .mocked(mockChannel.push)
        .mock.calls.map(([event]) => event);
      expect(asked).toEqual(['request_releases']);
      expect(store.getSnapshot().releases).toEqual([makeVersion()]);

      cleanup();
    });

    test('fetches releases from channel and updates state', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      const mockVersions: Release[] = [
        makeVersion({
          version_number: 3,
          kind: 'promote',
          source_project: 'staging',
          lock_version: 5,
          restored_from_version_number: null,
          inserted_at: '2024-01-15T10:30:00Z',
          is_latest: true,
        }),
        makeVersion({
          version_number: 2,
          lock_version: 4,
          restored_from_version_number: null,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: false,
        }),
        makeVersion({
          version_number: 1,
          lock_version: 3,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: false,
        }),
      ];

      // Configure channel to return releases
      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions,
      });

      // Initial state should be empty
      expect(store.getSnapshot().releases).toEqual([]);
      expect(store.getSnapshot().releasesLoading).toBe(false);

      // Request releases
      await store.requestReleases();

      // State should be updated with releases
      const state = store.getSnapshot();
      expect(state.releases).toEqual(mockVersions);
      expect(state.releasesLoading).toBe(false);
      expect(state.releasesError).toBe(null);

      cleanup();
    });

    test('sets loading state while fetching', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      const mockVersions: Release[] = [
        makeVersion({
          version_number: 1,
          lock_version: 3,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        }),
      ];

      // Configure channel with slight delay to observe loading state
      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions,
      });

      // Initial state
      expect(store.getSnapshot().releasesLoading).toBe(false);

      // Start request (don't await yet)
      const requestPromise = store.requestReleases();

      // Should be loading immediately
      expect(store.getSnapshot().releasesLoading).toBe(true);
      expect(store.getSnapshot().releasesError).toBe(null);

      // Wait for completion
      await requestPromise;

      // Should not be loading anymore
      expect(store.getSnapshot().releasesLoading).toBe(false);

      cleanup();
    });

    test('handles errors and sets releasesError', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      // Configure channel to return error
      mockChannel.push = createMockChannelPushError(
        'Failed to fetch releases',
        'versions_error'
      );

      // Request releases
      await store.requestReleases();

      // State should have error set
      const state = store.getSnapshot();
      expect(state.releasesLoading).toBe(false);
      expect(state.releasesError).toBe('Failed to load versions');
      expect(state.releases).toEqual([]);

      cleanup();
    });

    test('handles invalid releases data with validation error', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      // Configure channel to return invalid data (missing required fields)
      mockChannel.push = createMockChannelPushOk({
        releases: [
          {
            // Missing lock_version
            inserted_at: '2024-01-15T10:30:00Z',
            is_latest: true,
          },
        ],
      });

      // Request releases
      await store.requestReleases();

      // State should have validation error set
      const state = store.getSnapshot();
      expect(state.releasesLoading).toBe(false);
      expect(state.releasesError).toContain('Invalid versions data');
      expect(state.releases).toEqual([]);

      cleanup();
    });

    test('does not double-fetch if already loading (deduplication)', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      let pushCallCount = 0;
      const mockVersions: Release[] = [
        makeVersion({
          version_number: 1,
          lock_version: 2,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        }),
      ];

      // Track push calls
      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions,
      });

      // Wrap push to count calls
      const originalPush = mockChannel.push;
      mockChannel.push = (event: string, payload: unknown) => {
        if (event === 'request_releases') {
          pushCallCount++;
        }
        return originalPush(event, payload);
      };

      // Start first request (don't await)
      const request1 = store.requestReleases();

      // Immediately start second request while first is loading
      const request2 = store.requestReleases();

      // Wait for both to complete
      await Promise.all([request1, request2]);

      // Should only have called push once (deduplication)
      expect(pushCallCount).toBe(1);
      expect(store.getSnapshot().releases).toEqual(mockVersions);

      cleanup();
    });

    test('returns early if no channel provider', async () => {
      // Create store without connecting channel
      const store = createSessionContextStore();

      // Try to request releases without channel
      await store.requestReleases();

      // State should remain unchanged
      const state = store.getSnapshot();
      expect(state.releases).toEqual([]);
      expect(state.releasesLoading).toBe(false);
      expect(state.releasesError).toBe(null);
    });

    test('allows second request after first completes', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      const mockVersions1: Release[] = [
        makeVersion({
          version_number: 1,
          lock_version: 2,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        }),
      ];

      const mockVersions2: Release[] = [
        makeVersion({
          version_number: 2,
          lock_version: 3,
          restored_from_version_number: null,
          inserted_at: '2024-01-14T10:30:00Z',
          is_latest: true,
        }),
        makeVersion({
          version_number: 1,
          lock_version: 2,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: false,
        }),
      ];

      // First request
      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions1,
      });
      await store.requestReleases();
      expect(store.getSnapshot().releases).toEqual(mockVersions1);

      // Second request with different releases
      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions2,
      });
      await store.requestReleases();
      expect(store.getSnapshot().releases).toEqual(mockVersions2);

      cleanup();
    });

    test('handles empty releases array', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      // Configure channel to return empty array
      mockChannel.push = createMockChannelPushOk({
        releases: [],
      });

      // Request releases
      await store.requestReleases();

      // State should have empty array
      const state = store.getSnapshot();
      expect(state.releases).toEqual([]);
      expect(state.releasesLoading).toBe(false);
      expect(state.releasesError).toBe(null);

      // Nothing to show, but the question has been answered. Callers read this
      // rather than the list's length, which cannot tell "never published"
      // apart from "not asked yet".
      expect(state.releasesLoaded).toBe(true);

      cleanup();
    });

    test('records that it asked, even when the request fails', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      mockChannel.push = createMockChannelPushError({ reason: 'nope' });

      await store.requestReleases();

      const state = store.getSnapshot();
      expect(state.releasesError).toBe('Failed to load versions');
      expect(state.releasesLoaded).toBe(true);

      cleanup();
    });

    test('forgets it asked when the releases are invalidated', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      mockChannel.push = createMockChannelPushOk({ releases: [] });
      await store.requestReleases();
      expect(store.getSnapshot().releasesLoaded).toBe(true);

      // A save publishes a new version, so the answer is stale and the next
      // caller has to ask again.
      store.setLatestSnapshotLockVersion(1);
      store.setLatestSnapshotLockVersion(2);

      expect(store.getSnapshot().releasesLoaded).toBe(false);

      cleanup();
    });
  });

  describe('setLatestSnapshotLockVersion', () => {
    test('clears releases when lock version changes', () => {
      const { store, cleanup } = setupSessionContextStoreTest();

      // Set initial lock version (first time - from null)
      store.setLatestSnapshotLockVersion(1);

      // Manually populate releases
      const mockVersions: Release[] = [
        makeVersion({
          version_number: 1,
          lock_version: 1,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        }),
      ];

      // Directly modify state to add releases (simulating requestReleases)
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);
      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions,
      });
      store._connectChannel(mockProvider);

      // Request releases to populate state
      void store.requestReleases();
      // Wait for async operation
      waitForAsync().then(() => {
        expect(store.getSnapshot().releases).toEqual(mockVersions);

        // Change lock version (should clear releases)
        store.setLatestSnapshotLockVersion(2);

        // Versions should be cleared
        expect(store.getSnapshot().releases).toEqual([]);
        expect(store.getSnapshot().latestSnapshotLockVersion).toBe(2);

        cleanup();
      });
    });

    test('does NOT clear releases on initial set (null to number)', () => {
      const store = createSessionContextStore();

      // Initial state has null lock version
      expect(store.getSnapshot().latestSnapshotLockVersion).toBe(null);
      expect(store.getSnapshot().releases).toEqual([]);

      // Set lock version for first time (null → 1)
      store.setLatestSnapshotLockVersion(1);

      // Versions should NOT be cleared (still empty)
      expect(store.getSnapshot().releases).toEqual([]);
      expect(store.getSnapshot().latestSnapshotLockVersion).toBe(1);
    });

    test('clears releases when changing from one number to another', () => {
      const store = createSessionContextStore();

      // Set initial lock version
      store.setLatestSnapshotLockVersion(1);

      // Manually add releases to state for testing
      // This requires accessing internal state, so we'll use requestReleases
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      const mockVersions: Release[] = [
        makeVersion({
          version_number: 1,
          lock_version: 1,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        }),
      ];

      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions,
      });

      store._connectChannel(mockProvider);

      // Request releases to populate state
      store.requestReleases().then(() => {
        expect(store.getSnapshot().releases.length).toBeGreaterThan(0);

        // Change lock version (1 → 2)
        store.setLatestSnapshotLockVersion(2);

        // Versions should be cleared
        expect(store.getSnapshot().releases).toEqual([]);
        expect(store.getSnapshot().latestSnapshotLockVersion).toBe(2);
      });
    });

    test('does NOT clear releases when setting same lock version', () => {
      const store = createSessionContextStore();

      // Set initial lock version
      store.setLatestSnapshotLockVersion(1);

      // Add releases
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      const mockVersions: Release[] = [
        makeVersion({
          version_number: 1,
          lock_version: 1,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        }),
      ];

      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions,
      });

      store._connectChannel(mockProvider);

      // Request releases to populate state
      store.requestReleases().then(() => {
        expect(store.getSnapshot().releases.length).toBeGreaterThan(0);

        // Set same lock version (1 → 1)
        store.setLatestSnapshotLockVersion(1);

        // Versions should NOT be cleared
        expect(store.getSnapshot().releases).toEqual(mockVersions);
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

  describe('clearReleases', () => {
    test('empties the releases array', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      const mockVersions: Release[] = [
        makeVersion({
          version_number: 2,
          lock_version: 3,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        }),
        makeVersion({
          version_number: 1,
          lock_version: 2,
          restored_from_version_number: null,
          inserted_at: '2024-01-12T10:30:00Z',
          is_latest: false,
        }),
      ];

      // First, populate releases
      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions,
      });
      await store.requestReleases();

      // Verify releases are populated
      expect(store.getSnapshot().releases).toEqual(mockVersions);

      // Clear releases
      store.clearReleases();

      // Versions should be empty
      expect(store.getSnapshot().releases).toEqual([]);

      cleanup();
    });

    test('clearing already empty releases is safe', () => {
      const store = createSessionContextStore();

      // Initial state has empty releases
      expect(store.getSnapshot().releases).toEqual([]);

      // Clear releases (should be safe)
      store.clearReleases();

      // Still empty
      expect(store.getSnapshot().releases).toEqual([]);
    });

    test('does not affect other state properties', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      const mockVersions: Release[] = [
        makeVersion({
          version_number: 1,
          lock_version: 2,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        }),
      ];

      // Populate releases
      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions,
      });
      await store.requestReleases();

      // Set lock version
      store.setLatestSnapshotLockVersion(2);

      // Capture state before clear
      const beforeState = store.getSnapshot();
      expect(beforeState.releases).toEqual(mockVersions);
      expect(beforeState.latestSnapshotLockVersion).toBe(2);

      // Clear releases
      store.clearReleases();

      // Versions cleared but other properties unchanged
      const afterState = store.getSnapshot();
      expect(afterState.releases).toEqual([]);
      expect(afterState.latestSnapshotLockVersion).toBe(2);
      expect(afterState.user).toBe(beforeState.user);
      expect(afterState.project).toBe(beforeState.project);

      cleanup();
    });
  });

  describe('state notifications', () => {
    test('requestReleases notifies subscribers', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      let notificationCount = 0;
      store.subscribe(() => {
        notificationCount++;
      });

      const mockVersions: Release[] = [
        makeVersion({
          version_number: 1,
          lock_version: 2,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        }),
      ];

      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions,
      });

      // Request releases
      await store.requestReleases();

      // Should have notified subscribers (start loading + success)
      expect(notificationCount).toBeGreaterThan(0);

      cleanup();
    });

    test('clearReleases notifies subscribers', () => {
      const store = createSessionContextStore();

      let notificationCount = 0;
      store.subscribe(() => {
        notificationCount++;
      });

      // Clear releases
      store.clearReleases();

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
