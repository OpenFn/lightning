/**
 * useViewAsExecuted Hook Tests
 *
 * Verifies the hook produces the distinct `?as_run=<run_id>` param that
 * SessionProvider turns into the `:run:<run_id>` room, loading the workflow
 * read-only as that run executed. It must clear any release pin (`?v=`) and set
 * `run` for step highlighting, using the SPA URL update (no page reload).
 *
 * Pinning a run destroys the document, so it is also guarded: with unsaved
 * edits the hook asks first and offers to save.
 */

import { act, renderHook } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { useViewAsExecuted } from '../../../js/collaborative-editor/hooks/useViewAsExecuted';
import {
  createMockURLState,
  getURLStateMockValue,
} from '../__helpers__/urlStateMocks';

const urlState = createMockURLState();

vi.mock('../../../js/react/lib/use-url-state', () => ({
  useURLState: () => getURLStateMockValue(urlState),
}));

let hasChanges = false;
const saveWorkflow = vi.fn<() => Promise<unknown>>();

vi.mock('../../../js/collaborative-editor/hooks/useUnsavedChanges', () => ({
  useUnsavedChanges: () => ({ hasChanges }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: () => ({ isSynced: true }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowActions: () => ({ saveWorkflow }),
}));

describe('useViewAsExecuted', () => {
  beforeEach(() => {
    urlState.reset();
    hasChanges = false;
    saveWorkflow.mockReset();
    saveWorkflow.mockResolvedValue(undefined);
  });

  test('sets ?as_run and ?run for the run, clearing any ?v release pin', () => {
    urlState.setParam('v', '3'); // a stale release pin that must be cleared

    const { result } = renderHook(() => useViewAsExecuted());
    result.current.viewAsExecuted('run-abc');

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      v: null,
      as_run: 'run-abc',
      run: 'run-abc',
    });
  });

  test('returns a stable callback across renders', () => {
    const { result, rerender } = renderHook(() => useViewAsExecuted());
    const first = result.current.viewAsExecuted;
    rerender();
    expect(result.current.viewAsExecuted).toBe(first);
  });

  test('asks before pinning a run over unsaved changes', () => {
    hasChanges = true;

    const { result } = renderHook(() => useViewAsExecuted());
    act(() => {
      result.current.viewAsExecuted('run-abc');
    });

    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalled();
    expect(result.current.prompt.isAsking).toBe(true);
  });

  test('pins the run when the changes are discarded', () => {
    hasChanges = true;

    const { result } = renderHook(() => useViewAsExecuted());
    act(() => {
      result.current.viewAsExecuted('run-abc');
    });
    act(() => {
      result.current.prompt.runPending();
    });

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      v: null,
      as_run: 'run-abc',
      run: 'run-abc',
    });
    expect(result.current.prompt.isAsking).toBe(false);
  });

  test('saves first when asked, then pins the run', async () => {
    hasChanges = true;

    const { result } = renderHook(() => useViewAsExecuted());
    act(() => {
      result.current.viewAsExecuted('run-abc');
    });
    await act(async () => {
      await result.current.prompt.saveAndRunPending();
    });

    expect(saveWorkflow).toHaveBeenCalledWith({ notify: 'error-only' });
    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      v: null,
      as_run: 'run-abc',
      run: 'run-abc',
    });
  });

  test('a failed save keeps them on the document they were editing', async () => {
    hasChanges = true;
    saveWorkflow.mockRejectedValue(new Error('nope'));

    const { result } = renderHook(() => useViewAsExecuted());
    act(() => {
      result.current.viewAsExecuted('run-abc');
    });

    let saved: boolean | undefined;
    await act(async () => {
      saved = await result.current.prompt.saveAndRunPending();
    });

    expect(saved).toBe(false);
    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalled();
    expect(result.current.prompt.isAsking).toBe(true);
  });

  test('cancelling leaves the document alone', () => {
    hasChanges = true;

    const { result } = renderHook(() => useViewAsExecuted());
    act(() => {
      result.current.viewAsExecuted('run-abc');
    });
    act(() => {
      result.current.prompt.cancel();
    });

    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalled();
    expect(result.current.prompt.isAsking).toBe(false);
  });
});
