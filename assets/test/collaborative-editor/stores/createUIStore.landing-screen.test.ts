/**
 * createUIStore — landing screen slice tests
 *
 * Tests the showLandingScreen initial state and dismissLandingScreen command
 * in isolation against the real createUIStore implementation.
 *
 * Note: showLandingScreen starts true in the store; the useShowLandingScreen
 * hook gates visibility by also checking isNewWorkflow from SessionContextStore.
 */

import { describe, expect, test } from 'vitest';

import { createUIStore } from '../../../js/collaborative-editor/stores/createUIStore';

// =============================================================================
// INITIAL STATE
// =============================================================================

describe('createUIStore — landing screen initial state', () => {
  test('showLandingScreen starts as true', () => {
    const store = createUIStore();
    expect(store.getSnapshot().showLandingScreen).toBe(true);
  });
});

// =============================================================================
// dismissLandingScreen COMMAND
// =============================================================================

describe('createUIStore — dismissLandingScreen', () => {
  test('calling dismissLandingScreen() sets showLandingScreen to false', () => {
    const store = createUIStore();
    expect(store.getSnapshot().showLandingScreen).toBe(true);

    store.dismissLandingScreen();

    expect(store.getSnapshot().showLandingScreen).toBe(false);
  });

  test('calling dismissLandingScreen() on an already-dismissed store is a no-op', () => {
    const store = createUIStore();
    store.dismissLandingScreen();
    store.dismissLandingScreen();
    expect(store.getSnapshot().showLandingScreen).toBe(false);
  });
});
