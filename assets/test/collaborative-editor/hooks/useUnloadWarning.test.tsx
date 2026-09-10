/**
 * useUnloadWarning Hook Tests
 *
 * Closing the tab or following a link out of the editor is the one case our own
 * dialog cannot cover, so the browser's warning stands in. It must stay quiet
 * when there is nothing to lose, when the document has not synced yet, and for
 * a departure the person has already agreed to.
 */

import { renderHook } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { useUnloadWarning } from '../../../js/collaborative-editor/hooks/useUnloadWarning';
import {
  resetUnloadWarning,
  suppressUnloadWarning,
} from '../../../js/collaborative-editor/lib/unloadGuard';

let hasChanges = false;
let isSynced = true;
// The latch forgets it ever synced only when the document is replaced, which it
// reads off the provider's identity.
let provider: object | null = { id: 'provider-1' };

let experimentalFeatures = true;

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useExperimentalFeatures: () => experimentalFeatures,
}));

vi.mock('../../../js/collaborative-editor/hooks/useUnsavedChanges', () => ({
  useUnsavedChanges: () => ({ hasChanges }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: () => ({ provider, isSynced }),
}));

/** Fires a real beforeunload and reports whether anything asked to stay. */
function leavePage() {
  const event = new Event('beforeunload', { cancelable: true });
  window.dispatchEvent(event);
  return event.defaultPrevented;
}

describe('useUnloadWarning', () => {
  beforeEach(() => {
    hasChanges = false;
    experimentalFeatures = true;
    isSynced = true;
    provider = { id: 'provider-1' };
    resetUnloadWarning();
  });

  test('warns when leaving with unsaved changes', () => {
    hasChanges = true;
    renderHook(() => useUnloadWarning());

    expect(leavePage()).toBe(true);
  });

  test('says nothing to a user without experimental features', () => {
    // The warning is part of what this work added. Today closing the tab asks
    // nothing, and a user who did not opt in should get today's editor.
    experimentalFeatures = false;
    hasChanges = true;

    renderHook(() => useUnloadWarning());

    expect(leavePage()).toBe(false);
  });

  test('says nothing when there is nothing to lose', () => {
    renderHook(() => useUnloadWarning());

    expect(leavePage()).toBe(false);
  });

  test('says nothing before the document has synced', () => {
    hasChanges = true;
    isSynced = false;
    renderHook(() => useUnloadWarning());

    // An unsynced store is empty and so differs from the saved workflow, which
    // is not a change anyone made.
    expect(leavePage()).toBe(false);
  });

  test('stays quiet for a departure already agreed to', () => {
    hasChanges = true;
    renderHook(() => useUnloadWarning());

    suppressUnloadWarning();

    expect(leavePage()).toBe(false);
  });

  test('keeps warning through a dropped connection', () => {
    hasChanges = true;
    const { rerender } = renderHook(() => useUnloadWarning());

    // The websocket drops without the document being replaced, which is exactly
    // when unsaved work is most at risk.
    isSynced = false;
    rerender();

    expect(leavePage()).toBe(true);
  });

  test('a suppression does not outlive the page it was for', () => {
    hasChanges = true;
    renderHook(() => useUnloadWarning());

    suppressUnloadWarning();
    // Back from the browser's cache, or an abandoned navigation.
    window.dispatchEvent(new Event('pageshow'));

    expect(leavePage()).toBe(true);
  });

  test('stops warning once unmounted', () => {
    hasChanges = true;
    const { unmount } = renderHook(() => useUnloadWarning());
    unmount();

    expect(leavePage()).toBe(false);
  });
});
