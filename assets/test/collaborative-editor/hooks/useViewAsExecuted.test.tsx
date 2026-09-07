/**
 * useViewAsExecuted Hook Tests
 *
 * Verifies the hook produces the distinct `?as_run=<run_id>` param that
 * SessionProvider turns into the `:run:<run_id>` room, loading the workflow
 * read-only as that run executed. It must clear any release pin (`?v=`) and set
 * `run` for step highlighting, using the SPA URL update (no page reload).
 */

import { renderHook } from '@testing-library/react';
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

describe('useViewAsExecuted', () => {
  beforeEach(() => {
    urlState.reset();
  });

  test('sets ?as_run and ?run for the run, clearing any ?v release pin', () => {
    urlState.setParam('v', '3'); // a stale release pin that must be cleared

    const { result } = renderHook(() => useViewAsExecuted());
    result.current('run-abc');

    expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
      v: null,
      as_run: 'run-abc',
      run: 'run-abc',
    });
  });

  test('returns a stable callback across renders', () => {
    const { result, rerender } = renderHook(() => useViewAsExecuted());
    const first = result.current;
    rerender();
    expect(result.current).toBe(first);
  });
});
