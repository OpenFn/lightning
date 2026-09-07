/**
 * useVersionSelect Hook Tests
 *
 * Switching version updates the ?v param AND clears the selected run (?run),
 * so a run selected on one version never leaks into another (the Recent History
 * widget is version-scoped).
 */

import { renderHook } from '@testing-library/react';
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

describe('useVersionSelect', () => {
  beforeEach(() => {
    urlState.reset();
  });

  test('pinning a version sets ?v and clears ?run / ?as_run', () => {
    urlState.setParam('run', 'run-from-previous-version');

    const { result } = renderHook(() => useVersionSelect());
    result.current(3);

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      v: '3',
      run: null,
      as_run: null,
    });
  });

  test('returning to latest clears ?v, ?run and ?as_run', () => {
    urlState.setParam('run', 'run-from-previous-version');

    const { result } = renderHook(() => useVersionSelect());
    result.current('latest');

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      v: null,
      run: null,
      as_run: null,
    });
  });
});
