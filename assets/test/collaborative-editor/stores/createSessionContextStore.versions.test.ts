/**
 * Tests for `requestVersions`, the list of saved snapshots.
 *
 * The other numbering. Every save captures a snapshot, numbered by its own
 * `lock_version`; only a deliberate publish records a release. This is the list
 * a user without experimental features sees, and what `?v=` pins.
 *
 * It is a separate channel event from `request_releases` because the rows are
 * shaped differently, and both replies happen to carry a `lock_version` field.
 * One event answering either question would have let a client read the wrong
 * list without erroring — it would just have shown publishes where saves belong.
 */

import { describe, expect, test, vi } from 'vitest';

import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import type { Version } from '../../../js/collaborative-editor/types/sessionContext';
import {
  createMockChannelPushError,
  createMockChannelPushOk,
} from '../__helpers__/channelMocks';
import { setupSessionContextStoreTest } from '../__helpers__/storeHelpers';

const snapshot = (lock_version: number, is_latest = false): Version => ({
  lock_version,
  inserted_at: '2026-01-13T10:30:00Z',
  is_latest,
});

describe('createSessionContextStore - snapshot versions', () => {
  test('asks for the saves by their own name and keeps them', async () => {
    const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

    const versions = [snapshot(7, true), snapshot(6), snapshot(5)];
    mockChannel.push = createMockChannelPushOk({ versions });

    await store.requestVersions();

    const asked = vi
      .mocked(mockChannel.push)
      .mock.calls.map(([event]) => event);
    expect(asked).toEqual(['request_versions']);

    const state = store.getSnapshot();
    expect(state.versions).toEqual(versions);
    expect(state.versionsLoaded).toBe(true);
    expect(state.versionsLoading).toBe(false);
    expect(state.versionsError).toBe(null);

    // Asking one question must not answer the other. These two lists live side
    // by side so a session can switch pickers without one polluting the other.
    expect(state.releases).toEqual([]);
    expect(state.releasesLoaded).toBe(false);

    cleanup();
  });

  test('records that it asked, even when nothing came back', async () => {
    // A workflow with no snapshots answers with an empty list. Reading that as
    // "not fetched yet" asks again on every render for as long as the menu is
    // open, which is what the loaded flag is for.
    const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

    mockChannel.push = createMockChannelPushOk({ versions: [] });

    await store.requestVersions();

    expect(store.getSnapshot().versions).toEqual([]);
    expect(store.getSnapshot().versionsLoaded).toBe(true);

    cleanup();
  });

  test('a rejected request is still an answer', async () => {
    const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

    mockChannel.push = createMockChannelPushError('nope', 'versions_error');

    await store.requestVersions();

    const state = store.getSnapshot();
    expect(state.versionsError).toBe('Failed to load versions');
    expect(state.versionsLoaded).toBe(true);
    expect(state.versionsLoading).toBe(false);

    cleanup();
  });

  test('rows shaped like releases are refused', async () => {
    // A release row carries a lock_version too, so the shapes overlap enough
    // that reading the wrong reply would not obviously fail. It has no
    // is_latest-only shape though, and no version_number is expected here.
    const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

    mockChannel.push = createMockChannelPushOk({
      versions: [{ version_number: 1, kind: 'go_live' }],
    });

    await store.requestVersions();

    expect(store.getSnapshot().versionsError).toContain(
      'Invalid versions data'
    );
    expect(store.getSnapshot().versions).toEqual([]);

    cleanup();
  });

  test('does not ask twice while the first request is in flight', async () => {
    const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

    mockChannel.push = createMockChannelPushOk({ versions: [snapshot(1)] });

    await Promise.all([store.requestVersions(), store.requestVersions()]);

    const asked = vi
      .mocked(mockChannel.push)
      .mock.calls.filter(([event]) => event === 'request_versions');
    expect(asked).toHaveLength(1);

    cleanup();
  });

  test('clearVersions forgets both the list and that it asked', async () => {
    const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

    mockChannel.push = createMockChannelPushOk({ versions: [snapshot(1)] });
    await store.requestVersions();
    expect(store.getSnapshot().versionsLoaded).toBe(true);

    store.clearVersions();

    expect(store.getSnapshot().versions).toEqual([]);
    expect(store.getSnapshot().versionsLoaded).toBe(false);

    cleanup();
  });
});
