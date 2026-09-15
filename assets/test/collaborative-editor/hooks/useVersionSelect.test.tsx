
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

let hasChanges = false;
const saveWorkflow = vi.fn<() => Promise<unknown>>();

vi.mock('../../../js/collaborative-editor/hooks/useUnsavedChanges', () => ({
  useUnsavedChanges: () => ({ hasChanges }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: () => ({ isSynced: true, settled: true }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowActions: () => ({ saveWorkflow }),
}));

let picker: 'releases' | 'snapshots' = 'releases';

vi.mock('../../../js/collaborative-editor/hooks/useVersionPicker', () => ({
  useVersionPicker: () => picker,
}));

let experimentalFeatures = true;

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useSessionContextError: () => null,
  useExperimentalFeatures: () => experimentalFeatures,
}));

describe('useVersionSelect', () => {
  beforeEach(() => {
    urlState.reset();
    hasChanges = false;
    experimentalFeatures = true;
    picker = 'releases';
    saveWorkflow.mockReset();
    saveWorkflow.mockResolvedValue(undefined);
  });

  test('pinning a version sets ?release and clears ?run / ?as_run', () => {
    urlState.setParam('run', 'run-from-previous-version');

    const { result } = renderHook(() => useVersionSelect());
    result.current.handleVersionSelect(3);

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      release: '3',
      v: null,
      run: null,
      as_run: null,
      step: null,
    });
  });

  test('pins a snapshot with ?v, and touches nothing else, on the snapshots picker', () => {
    picker = 'snapshots';
    urlState.setParam('run', 'the-run-being-looked-at');

    const { result } = renderHook(() => useVersionSelect());
    result.current.handleVersionSelect(3);

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      release: null,
      as_run: null,
      v: '3',
    });
  });

  test('clears a pin it could not have made itself', () => {
    picker = 'snapshots';
    urlState.setParam('as_run', 'a-run-from-a-shared-link');

    const { result } = renderHook(() => useVersionSelect());
    result.current.handleVersionSelect(3);

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith(
      expect.objectContaining({ as_run: null, release: null })
    );
  });

  test('returning to latest on the snapshots picker clears only the pins', () => {
    picker = 'snapshots';

    const { result } = renderHook(() => useVersionSelect());
    result.current.handleVersionSelect('latest');

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      release: null,
      as_run: null,
      v: null,
    });
  });

  test('returning to latest clears the version pins, ?run and ?as_run', () => {
    urlState.setParam('run', 'run-from-previous-version');

    const { result } = renderHook(() => useVersionSelect());
    result.current.handleVersionSelect('latest');

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      release: null,
      v: null,
      run: null,
      as_run: null,
      step: null,
    });
  });

  test('switches straight away without experimental features', () => {
    experimentalFeatures = false;
    picker = 'snapshots';
    hasChanges = true;

    const { result } = renderHook(() => useVersionSelect());

    act(() => {
      result.current.handleVersionSelect(3);
    });

    expect(result.current.prompt.isAsking).toBe(false);
    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith(
      expect.objectContaining({ v: '3' })
    );
  });

  test('asks on the snapshots picker too, which is where the edits are', () => {
    picker = 'snapshots';
    hasChanges = true;

    const { result } = renderHook(() => useVersionSelect());

    act(() => {
      result.current.handleVersionSelect(3);
    });

    expect(result.current.prompt.isAsking).toBe(true);
    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalled();
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

    act(() => {
      result.current.prompt.runPending();
    });

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      release: '3',
      v: null,
      run: null,
      as_run: null,
      step: null,
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
      release: '3',
      v: null,
      run: null,
      as_run: null,
      step: null,
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

    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalled();
  });
});
