/**
 * URL State Mock Helpers
 *
 * Centralized mock for useURLState hook used across collaborative editor tests.
 * Provides a consistent, controllable mock that matches the real hook's API.
 *
 * The real useURLState returns:
 * - params: Record<string, string> - current URL search params
 * - hash: string - current URL hash (without #)
 * - updateSearchParams: (updates) => void - merge updates into params
 * - replaceSearchParams: (newParams) => void - replace all params
 * - updateHash: (hash) => void - update hash
 *
 * @example
 * // In test file:
 * import { createMockURLState } from './__helpers__';
 *
 * const { mockParams, mockFns, reset } = createMockURLState();
 *
 * vi.mock('../../../js/react/lib/use-url-state', () => ({
 *   useURLState: () => ({
 *     params: mockParams,
 *     hash: '',
 *     ...mockFns,
 *   }),
 * }));
 *
 * // In tests:
 * mockParams.panel = 'editor';
 * mockParams.job = 'job-1';
 *
 * // In beforeEach:
 * reset();
 */

import { vi } from 'vitest';

/**
 * Mock function types for useURLState
 */
export interface URLStateMockFns {
  updateSearchParams: ReturnType<typeof vi.fn>;
  replaceSearchParams: ReturnType<typeof vi.fn>;
  updateHash: ReturnType<typeof vi.fn>;
}

/**
 * Return type from createMockURLState
 */
export interface URLStateMock {
  /** Mutable params object - set values directly: mockParams.panel = 'editor' */
  mockParams: Record<string, string>;
  /** Mock functions for updateSearchParams, replaceSearchParams, updateHash */
  mockFns: URLStateMockFns;
  /** Reset all params and clear mock function calls */
  reset: () => void;
  /** Set a single param */
  setParam: (key: string, value: string) => void;
  /** Delete a single param */
  deleteParam: (key: string) => void;
  /** Set multiple params at once */
  setParams: (params: Record<string, string>) => void;
  /** Clear all params */
  clearParams: () => void;
}

/**
 * Creates a controllable mock for useURLState hook.
 *
 * Returns an object with:
 * - mockParams: Mutable object to set URL params
 * - mockFns: Mock functions (updateSearchParams, replaceSearchParams, updateHash)
 * - Helper methods: reset(), setParam(), deleteParam(), setParams(), clearParams()
 *
 * @example
 * const urlState = createMockURLState();
 *
 * // Set params for test
 * urlState.setParams({ panel: 'editor', job: 'job-1' });
 *
 * // Or set directly
 * urlState.mockParams.panel = 'editor';
 *
 * // Check if updateSearchParams was called
 * expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({ panel: 'editor' });
 *
 * // Reset between tests
 * urlState.reset();
 */
export function createMockURLState(): URLStateMock {
  const mockParams: Record<string, string> = {};

  const mockFns: URLStateMockFns = {
    updateSearchParams: vi.fn(),
    replaceSearchParams: vi.fn(),
    updateHash: vi.fn(),
  };

  const clearParams = () => {
    for (const key of Object.keys(mockParams)) {
      delete mockParams[key];
    }
  };

  const reset = () => {
    clearParams();
    mockFns.updateSearchParams.mockClear();
    mockFns.replaceSearchParams.mockClear();
    mockFns.updateHash.mockClear();
  };

  const setParam = (key: string, value: string) => {
    mockParams[key] = value;
  };

  const deleteParam = (key: string) => {
    delete mockParams[key];
  };

  const setParams = (params: Record<string, string>) => {
    Object.assign(mockParams, params);
  };

  return {
    mockParams,
    mockFns,
    reset,
    setParam,
    deleteParam,
    setParams,
    clearParams,
  };
}

/**
 * Creates the mock implementation object for vi.mock().
 *
 * This is a convenience function that returns the object shape expected
 * by the useURLState mock.
 *
 * @param urlStateMock - The mock created by createMockURLState()
 * @param hash - Optional hash value (defaults to '')
 * @returns Object to spread into useURLState mock return value
 *
 * @example
 * const urlState = createMockURLState();
 *
 * vi.mock('../../../js/react/lib/use-url-state', () => ({
 *   useURLState: () => getURLStateMockValue(urlState),
 * }));
 */
export function getURLStateMockValue(
  urlStateMock: URLStateMock,
  hash: string = ''
) {
  return {
    params: urlStateMock.mockParams,
    hash,
    ...urlStateMock.mockFns,
  };
}

/**
 * Type for the return value of useURLState hook
 * Useful for typing mock implementations
 */
export interface UseURLStateReturn {
  params: Record<string, string>;
  hash: string;
  updateSearchParams: (
    updates: Record<string, string | number | boolean | null>
  ) => void;
  replaceSearchParams: (
    newParams: Record<string, string | number | boolean | null>
  ) => void;
  updateHash: (hash: string | null) => void;
}
