/**
 * createUIStore — landing screen slice tests
 *
 * Tests the showLandingScreen initial state and dismissLandingScreen command
 * in isolation against the real createUIStore implementation.
 */

import { describe, expect, test } from 'vitest';

import { createUIStore } from '../../../js/collaborative-editor/stores/createUIStore';

// =============================================================================
// INITIAL STATE
// =============================================================================

describe('createUIStore — landing screen initial state', () => {
  test('createUIStore(true) — showLandingScreen starts as true', () => {
    const store = createUIStore(true);
    expect(store.getSnapshot().showLandingScreen).toBe(true);
  });

  test('createUIStore(false) — showLandingScreen starts as false', () => {
    const store = createUIStore(false);
    expect(store.getSnapshot().showLandingScreen).toBe(false);
  });

  test('createUIStore() with no argument — showLandingScreen starts as false', () => {
    const store = createUIStore();
    expect(store.getSnapshot().showLandingScreen).toBe(false);
  });
});

// =============================================================================
// dismissLandingScreen COMMAND
// =============================================================================

describe('createUIStore — dismissLandingScreen', () => {
  test('calling dismissLandingScreen() sets showLandingScreen to false', () => {
    const store = createUIStore(true);
    expect(store.getSnapshot().showLandingScreen).toBe(true);

    store.dismissLandingScreen();

    expect(store.getSnapshot().showLandingScreen).toBe(false);
  });

  test('calling dismissLandingScreen() on an already-dismissed store is a no-op', () => {
    const store = createUIStore(false);
    store.dismissLandingScreen();
    expect(store.getSnapshot().showLandingScreen).toBe(false);
  });
});
