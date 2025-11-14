/**
 * Tests for setupUIStoreTest helper
 *
 * Verifies that the helper creates a properly configured UIStore
 * instance for testing.
 */

import { describe, it, expect } from 'vitest';

import { setupUIStoreTest } from './storeHelpers';

describe('setupUIStoreTest', () => {
  it('creates a UIStore instance with initial state', () => {
    const { store, cleanup } = setupUIStoreTest();

    const state = store.getSnapshot();

    expect(state.runPanelOpen).toBe(false);
    expect(state.runPanelContext).toBe(null);
    expect(state.githubSyncModalOpen).toBe(false);

    cleanup();
  });

  it('provides working store methods', () => {
    const { store, cleanup } = setupUIStoreTest();

    // Test openRunPanel command
    store.openRunPanel({ jobId: 'job-1' });
    let state = store.getSnapshot();
    expect(state.runPanelOpen).toBe(true);
    expect(state.runPanelContext?.jobId).toBe('job-1');

    // Test closeRunPanel command
    store.closeRunPanel();
    state = store.getSnapshot();
    expect(state.runPanelOpen).toBe(false);
    expect(state.runPanelContext).toBe(null);

    cleanup();
  });

  it('provides working subscription mechanism', () => {
    const { store, cleanup } = setupUIStoreTest();

    let notificationCount = 0;
    const unsubscribe = store.subscribe(() => {
      notificationCount++;
    });

    // Open panel - should trigger notification
    store.openRunPanel({ triggerId: 'trigger-1' });
    expect(notificationCount).toBe(1);

    // Close panel - should trigger notification
    store.closeRunPanel();
    expect(notificationCount).toBe(2);

    unsubscribe();
    cleanup();
  });

  it('provides working withSelector utility', () => {
    const { store, cleanup } = setupUIStoreTest();

    // Create a memoized selector
    const selector = store.withSelector(state => state.runPanelOpen);

    // Initial state
    expect(selector(store.getSnapshot())).toBe(false);

    // After opening panel
    store.openRunPanel({ jobId: 'job-2' });
    expect(selector(store.getSnapshot())).toBe(true);

    cleanup();
  });

  it('supports GitHub sync modal commands', () => {
    const { store, cleanup } = setupUIStoreTest();

    // Open modal
    store.openGitHubSyncModal();
    let state = store.getSnapshot();
    expect(state.githubSyncModalOpen).toBe(true);

    // Close modal
    store.closeGitHubSyncModal();
    state = store.getSnapshot();
    expect(state.githubSyncModalOpen).toBe(false);

    cleanup();
  });

  it('handles cleanup gracefully', () => {
    const { store, cleanup } = setupUIStoreTest();

    // Perform some operations
    store.openRunPanel({ jobId: 'job-3' });
    store.openGitHubSyncModal();

    // Cleanup should not throw
    expect(() => cleanup()).not.toThrow();

    // Store should still be accessible after cleanup
    const state = store.getSnapshot();
    expect(state).toBeDefined();
  });
});
