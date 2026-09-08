/**
 * useVersionSelect Hook Tests
 *
 * Switching version updates the ?v param AND clears the selected run (?run),
 * so a run selected on one version never leaks into another (the Recent History
 * widget is version-scoped).
 */

import { act, renderHook } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { useVersionSelect } from '../../../js/collaborative-editor/hooks/useVersionSelect';
import {
  createMockURLState,
  getURLStateMockValue,
} from '../__helpers__/urlStateMocks';

const urlState = createMockURLState();

vi.mock('../../../js/react/lib/use-url-state', () => ({
  useURLState: () => getURLStateMockValue(urlState),
}));

// The switch is guarded, so the hook needs to know whether there is anything to
// lose and how to save it.
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

describe('useVersionSelect', () => {
  beforeEach(() => {
    urlState.reset();
    hasChanges = false;
    saveWorkflow.mockReset();
    saveWorkflow.mockResolvedValue(undefined);
  });

  test('pinning a version sets ?v and clears ?run / ?as_run', () => {
    urlState.setParam('run', 'run-from-previous-version');

    const { result } = renderHook(() => useVersionSelect());
    result.current.handleVersionSelect(3);

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      v: '3',
      run: null,
      as_run: null,
    });
  });

  test('returning to latest clears ?v, ?run and ?as_run', () => {
    urlState.setParam('run', 'run-from-previous-version');

    const { result } = renderHook(() => useVersionSelect());
    result.current.handleVersionSelect('latest');

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      v: null,
      run: null,
      as_run: null,
    });
  });

  test('asks first when there are unsaved changes, and switches nothing yet', () => {
    hasChanges = true;

    const { result } = renderHook(() => useVersionSelect());

    act(() => {
      result.current.handleVersionSelect(3);
    });

    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalled();
    expect(result.current.prompt.isAsking).toBe(true);
  });

  test('switching anyway discards and goes', async () => {
    hasChanges = true;

    const { result } = renderHook(() => useVersionSelect());

    act(() => {
      result.current.handleVersionSelect(3);
    });

    await act(async () => {
      result.current.prompt.runPending();
    });

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      v: '3',
      run: null,
      as_run: null,
    });
  });

  test('saving first switches only once the save succeeded', async () => {
    hasChanges = true;

    const { result } = renderHook(() => useVersionSelect());

    act(() => {
      result.current.handleVersionSelect(3);
    });

    await act(async () => {
      await result.current.prompt.saveAndRunPending();
    });

    expect(saveWorkflow).toHaveBeenCalledWith({ notify: 'error-only' });
    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      v: '3',
      run: null,
      as_run: null,
    });
  });

  test('a failed save keeps them where they are', async () => {
    hasChanges = true;
    saveWorkflow.mockRejectedValue(new Error('nope'));

    const { result } = renderHook(() => useVersionSelect());

    act(() => {
      result.current.handleVersionSelect(3);
    });

    await act(async () => {
      const switched = await result.current.prompt.saveAndRunPending();
      expect(switched).toBe(false);
    });

    // Losing the edits because the save failed is the whole thing we are
    // trying to prevent.
    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalled();
  });
});
