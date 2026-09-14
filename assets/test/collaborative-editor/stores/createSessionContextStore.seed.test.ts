/**
 * The experimental flag is seeded from the page, not waited for.
 *
 * Everything the editor shows differently under this feature hangs off that
 * flag, and it used to arrive with the session context, a round trip after the
 * first paint. Until it landed the editor drew the flag-off header and then
 * corrected itself: on a live workflow the Save button appeared and vanished.
 * The context still carries the flag and still wins; this is only its opening
 * value, so there is one source of truth rather than two.
 */

import { describe, expect, test } from 'vitest';

import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';

describe('createSessionContextStore - the experimental flag on first paint', () => {
  test('defaults to off when the page says nothing', () => {
    const store = createSessionContextStore();

    expect(store.getSnapshot().experimentalFeaturesEnabled).toBe(false);
  });

  test('is on before any context has arrived when the page says so', () => {
    const store = createSessionContextStore(false, true);

    expect(store.getSnapshot().experimentalFeaturesEnabled).toBe(true);
  });
});
