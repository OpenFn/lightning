
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
