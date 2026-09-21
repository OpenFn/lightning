
import { renderHook } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { useUnloadWarning } from '../../../js/collaborative-editor/hooks/useUnloadWarning';
import {
  resetUnloadWarning,
  suppressUnloadWarning,
} from '../../../js/collaborative-editor/lib/unloadGuard';

let hasChanges = false;
let isSynced = true;
let provider: object | null = { id: 'provider-1' };

let experimentalFeatures = true;

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useSessionContextError: () => null,
  useSessionContextLoaded: () => true,
  useRequestVersions: () => vi.fn(),
  useVersionsError: () => null,
  useVersionsLoading: () => false,
  useVersionsLoaded: () => true,
  useSessionWorkflow: () => null,
  useContentLocked: () => false,
  useVersions: () => [],
  useExperimentalFeatures: () => experimentalFeatures,
}));

vi.mock('../../../js/collaborative-editor/hooks/useUnsavedChanges', () => ({
  useUnsavedChanges: () => ({ hasChanges }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: () => ({ provider, isSynced, settled: true }),
}));

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

    isSynced = false;
    rerender();

    expect(leavePage()).toBe(true);
  });

  test('a suppression does not outlive the page it was for', () => {
    hasChanges = true;
    renderHook(() => useUnloadWarning());

    suppressUnloadWarning();
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
