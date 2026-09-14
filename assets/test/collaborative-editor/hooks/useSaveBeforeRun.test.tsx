import { renderHook } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { useSaveBeforeRun } from '../../../js/collaborative-editor/hooks/useSaveBeforeRun';

let contentLocked = false;
let pinnedView = false;

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useContentLocked: () => contentLocked,
}));

vi.mock('../../../js/collaborative-editor/lib/pinnedView', () => ({
  usePinnedView: () => ({ isPinnedView: pinnedView }),
}));

describe('useSaveBeforeRun', () => {
  test('saves on the way to a run, and says it did', async () => {
    contentLocked = false;
    pinnedView = false;
    const saveWorkflow = vi.fn().mockResolvedValue({});

    const { result } = renderHook(() => useSaveBeforeRun(saveWorkflow));

    await expect(result.current()).resolves.toBe(true);
    expect(saveWorkflow).toHaveBeenCalledWith({ notify: 'none' });
  });

  test('skips the save on a live workflow', async () => {
    // The server refuses it, and refusing it aborted the run. Running is not
    // editing, so the run goes ahead without the save.
    contentLocked = true;
    pinnedView = false;
    const saveWorkflow = vi.fn().mockResolvedValue({});

    const { result } = renderHook(() => useSaveBeforeRun(saveWorkflow));

    await expect(result.current()).resolves.toBe(false);
    expect(saveWorkflow).not.toHaveBeenCalled();
  });

  test('skips the save while reading an older version, locked or not', async () => {
    // A view of a draft, or of anything in a sandbox, is not content-locked but
    // is still refused a save. Gating on the lock alone let these through and
    // the retry they were on their way to died with the read-only error.
    contentLocked = false;
    pinnedView = true;
    const saveWorkflow = vi.fn().mockResolvedValue({});

    const { result } = renderHook(() => useSaveBeforeRun(saveWorkflow));

    await expect(result.current()).resolves.toBe(false);
    expect(saveWorkflow).not.toHaveBeenCalled();
  });
});
