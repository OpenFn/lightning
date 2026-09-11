/**
 * useVersionSelect Hook Tests
 *
 * Switching version updates the pin parameter. With experimental features on it
 * also clears the selected run (?run), so a run selected on one version never
 * leaks into another. Without them it writes the snapshot parameter the editor
 * writes today, clears the two pins it could not have made itself, and leaves
 * the open run alone.
 *
 * Which parameter it writes depends on the picker the user has: `?release=` for
 * the publish trail with experimental features on, `?v=` for a snapshot's own
 * lock_version without. The two numbers mean different content, so writing one
 * into the other's parameter would open the wrong document.
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

let experimentalFeatures = true;

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useExperimentalFeatures: () => experimentalFeatures,
}));

describe('useVersionSelect', () => {
  beforeEach(() => {
    urlState.reset();
    hasChanges = false;
    experimentalFeatures = true;
    saveWorkflow.mockReset();
    saveWorkflow.mockResolvedValue(undefined);
  });

  test('pinning a version sets ?release and clears ?run / ?as_run', () => {
    urlState.setParam('run', 'run-from-previous-version');

    const { result } = renderHook(() => useVersionSelect());
    result.current.handleVersionSelect(3);

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      release: '3',
      // Both numbering schemes are cleared, so a bookmark carrying the other one
      // cannot survive the switch and pin the view straight back.
      v: null,
      run: null,
      as_run: null,
      step: null,
    });
  });

  test('pins a snapshot with ?v, and touches nothing else, without the flag', () => {
    // Without the flag the picker lists saves, numbered by lock_version, and
    // those go in `?v=`. Writing them into `?release=` would ask the server for
    // release 3 and get whichever content that published, which is a different
    // snapshot.
    //
    // It clears no other parameter either. The open run survives the switch,
    // which is what the mismatch banner's offer depends on: it takes you to the
    // version the run ran against, and the run has to still be there when you
    // arrive.
    experimentalFeatures = false;
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
    // A flag-off user cannot produce ?as_run= or ?release=, but a link from
    // someone who can carries them in, and the room name resolves those before
    // the snapshot. Leaving them would let this picker change the URL and
    // nothing else.
    experimentalFeatures = false;
    urlState.setParam('as_run', 'a-run-from-a-shared-link');

    const { result } = renderHook(() => useVersionSelect());
    result.current.handleVersionSelect(3);

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith(
      expect.objectContaining({ as_run: null, release: null })
    );
  });

  test('returning to latest without the flag clears only the pins', () => {
    experimentalFeatures = false;

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
    // The prompt is part of what this work added. Today the editor discards
    // silently, so a user who did not opt in must not meet a dialog they have
    // never seen.
    experimentalFeatures = false;
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
      // Both numbering schemes are cleared, so a bookmark carrying the other one
      // cannot survive the switch and pin the view straight back.
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
      // Both numbering schemes are cleared, so a bookmark carrying the other one
      // cannot survive the switch and pin the view straight back.
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

    // Losing the edits because the save failed is the whole thing we are
    // trying to prevent.
    expect(urlState.mockFns.updateSearchParams).not.toHaveBeenCalled();
  });
});
