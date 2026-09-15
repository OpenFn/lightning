
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

      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions,
      });

      expect(store.getSnapshot().releases).toEqual([]);
      expect(store.getSnapshot().releasesLoading).toBe(false);

      await store.requestReleases();

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

      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions,
      });

      expect(store.getSnapshot().releasesLoading).toBe(false);

      const requestPromise = store.requestReleases();

      expect(store.getSnapshot().releasesLoading).toBe(true);
      expect(store.getSnapshot().releasesError).toBe(null);

      await requestPromise;

      expect(store.getSnapshot().releasesLoading).toBe(false);

      cleanup();
    });

    test('handles errors and sets releasesError', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      mockChannel.push = createMockChannelPushError(
        'Failed to fetch releases',
        'versions_error'
      );

      await store.requestReleases();

      const state = store.getSnapshot();
      expect(state.releasesLoading).toBe(false);
      expect(state.releasesError).toBe('Failed to load versions');
      expect(state.releases).toEqual([]);

      cleanup();
    });

    test('handles invalid releases data with validation error', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      mockChannel.push = createMockChannelPushOk({
        releases: [
          {
            inserted_at: '2024-01-15T10:30:00Z',
            is_latest: true,
          },
        ],
      });

      await store.requestReleases();

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

      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions,
      });

      const originalPush = mockChannel.push;
      mockChannel.push = (event: string, payload: unknown) => {
        if (event === 'request_releases') {
          pushCallCount++;
        }
        return originalPush(event, payload);
      };

      const request1 = store.requestReleases();

      const request2 = store.requestReleases();

      await Promise.all([request1, request2]);

      expect(pushCallCount).toBe(1);
      expect(store.getSnapshot().releases).toEqual(mockVersions);

      cleanup();
    });

    test('returns early if no channel provider', async () => {
      const store = createSessionContextStore();

      await store.requestReleases();

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

      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions1,
      });
      await store.requestReleases();
      expect(store.getSnapshot().releases).toEqual(mockVersions1);

      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions2,
      });
      await store.requestReleases();
      expect(store.getSnapshot().releases).toEqual(mockVersions2);

      cleanup();
    });

    test('handles empty releases array', async () => {
      const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

      mockChannel.push = createMockChannelPushOk({
        releases: [],
      });

      await store.requestReleases();

      const state = store.getSnapshot();
      expect(state.releases).toEqual([]);
      expect(state.releasesLoading).toBe(false);
      expect(state.releasesError).toBe(null);

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

      store.setLatestSnapshotLockVersion(1);
      store.setLatestSnapshotLockVersion(2);

      expect(store.getSnapshot().releasesLoaded).toBe(false);

      cleanup();
    });
  });

  describe('setLatestSnapshotLockVersion', () => {
    test('clears releases when lock version changes', () => {
      const { store, cleanup } = setupSessionContextStoreTest();

      store.setLatestSnapshotLockVersion(1);

      const mockVersions: Release[] = [
        makeVersion({
          version_number: 1,
          lock_version: 1,
          restored_from_version_number: null,
          inserted_at: '2024-01-13T10:30:00Z',
          is_latest: true,
        }),
      ];

      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);
      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions,
      });
      store._connectChannel(mockProvider);

      void store.requestReleases();
      waitForAsync().then(() => {
        expect(store.getSnapshot().releases).toEqual(mockVersions);

        store.setLatestSnapshotLockVersion(2);

        expect(store.getSnapshot().releases).toEqual([]);
        expect(store.getSnapshot().latestSnapshotLockVersion).toBe(2);

        cleanup();
      });
    });

    test('does NOT clear releases on initial set (null to number)', () => {
      const store = createSessionContextStore();

      expect(store.getSnapshot().latestSnapshotLockVersion).toBe(null);
      expect(store.getSnapshot().releases).toEqual([]);

      store.setLatestSnapshotLockVersion(1);

      expect(store.getSnapshot().releases).toEqual([]);
      expect(store.getSnapshot().latestSnapshotLockVersion).toBe(1);
    });

    test('clears releases when changing from one number to another', () => {
      const store = createSessionContextStore();

      store.setLatestSnapshotLockVersion(1);

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

      store.requestReleases().then(() => {
        expect(store.getSnapshot().releases.length).toBeGreaterThan(0);

        store.setLatestSnapshotLockVersion(2);

        expect(store.getSnapshot().releases).toEqual([]);
        expect(store.getSnapshot().latestSnapshotLockVersion).toBe(2);
      });
    });

    test('does NOT clear releases when setting same lock version', () => {
      const store = createSessionContextStore();

      store.setLatestSnapshotLockVersion(1);

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

      store.requestReleases().then(() => {
        expect(store.getSnapshot().releases.length).toBeGreaterThan(0);

        store.setLatestSnapshotLockVersion(1);

        expect(store.getSnapshot().releases).toEqual(mockVersions);
        expect(store.getSnapshot().latestSnapshotLockVersion).toBe(1);
      });
    });

    test('updates lastUpdated timestamp', () => {
      const store = createSessionContextStore();

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

      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions,
      });
      await store.requestReleases();

      expect(store.getSnapshot().releases).toEqual(mockVersions);

      store.clearReleases();

      expect(store.getSnapshot().releases).toEqual([]);

      cleanup();
    });

    test('clearing already empty releases is safe', () => {
      const store = createSessionContextStore();

      expect(store.getSnapshot().releases).toEqual([]);

      store.clearReleases();

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

      mockChannel.push = createMockChannelPushOk({
        releases: mockVersions,
      });
      await store.requestReleases();

      store.setLatestSnapshotLockVersion(2);

      const beforeState = store.getSnapshot();
      expect(beforeState.releases).toEqual(mockVersions);
      expect(beforeState.latestSnapshotLockVersion).toBe(2);

      store.clearReleases();

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

      await store.requestReleases();

      expect(notificationCount).toBeGreaterThan(0);

      cleanup();
    });

    test('clearReleases notifies subscribers', () => {
      const store = createSessionContextStore();

      let notificationCount = 0;
      store.subscribe(() => {
        notificationCount++;
      });

      store.clearReleases();

      expect(notificationCount).toBe(1);
    });

    test('setLatestSnapshotLockVersion notifies subscribers', () => {
      const store = createSessionContextStore();

      let notificationCount = 0;
      store.subscribe(() => {
        notificationCount++;
      });

      store.setLatestSnapshotLockVersion(1);

      expect(notificationCount).toBe(1);
    });
  });
});
