/**
 * useURLState Hook Tests
 *
 * Tests for the singleton URL state manager that synchronizes with browser URL.
 * Validates:
 * - Basic functionality (reading/updating search params and hash)
 * - Reactivity (re-renders on changes from hook, history API, and browser navigation)
 * - Singleton behavior (shared state across multiple hook instances)
 * - Reference stability: Uses Record<string, string> with Immer structural sharing
 *   to ensure only changed params create new references
 */

import { renderHook, act } from '@testing-library/react';
import { describe, test, expect, beforeEach } from 'vitest';

import { useURLState } from '../../../js/react/lib/use-url-state';

describe('useURLState', () => {
  beforeEach(() => {
    // Reset URL to clean state for each test
    // Use replaceState to avoid polluting browser history during tests
    history.replaceState({}, '', '/');

    // Note: The URLStore singleton is created at module load time, so it will
    // already have monkey-patched history methods. We're testing the actual
    // implementation as-is, including the monkey-patching behavior.
  });

  // ==========================================================================
  // Basic Functionality - Reading State
  // ==========================================================================

  describe('reading state', () => {
    test('returns empty params object for URL with no query string', () => {
      history.replaceState({}, '', '/workflow');

      const { result } = renderHook(() => useURLState());

      expect(result.current.params).toEqual({});
    });

    test('returns current search params from URL', () => {
      history.replaceState({}, '', '/workflow?panel=run&job=abc123');

      const { result } = renderHook(() => useURLState());

      expect(result.current.params.panel).toBe('run');
      expect(result.current.params.job).toBe('abc123');
    });

    test('returns empty hash for URL with no hash', () => {
      history.replaceState({}, '', '/workflow');

      const { result } = renderHook(() => useURLState());

      expect(result.current.hash).toBe('');
    });

    test('returns current hash from URL', () => {
      history.replaceState({}, '', '/workflow#step-5');

      const { result } = renderHook(() => useURLState());

      expect(result.current.hash).toBe('step-5');
    });

    test('returns both search params and hash together', () => {
      history.replaceState({}, '', '/workflow?panel=run&job=xyz#step-2');

      const { result } = renderHook(() => useURLState());

      expect(result.current.params.panel).toBe('run');
      expect(result.current.params.job).toBe('xyz');
      expect(result.current.hash).toBe('step-2');
    });
  });

  // ==========================================================================
  // Basic Functionality - Updating State
  // ==========================================================================

  describe('updateSearchParams', () => {
    test('adds new search param to URL', () => {
      history.replaceState({}, '', '/workflow');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateSearchParams({ panel: 'run' });
      });

      expect(result.current.params.panel).toBe('run');
      expect(window.location.search).toBe('?panel=run');
    });

    test('updates existing search param in URL', () => {
      history.replaceState({}, '', '/workflow?panel=run&job=abc');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateSearchParams({ job: 'xyz' });
      });

      expect(result.current.params.panel).toBe('run');
      expect(result.current.params.job).toBe('xyz');
    });

    test('removes search param when value is null', () => {
      history.replaceState({}, '', '/workflow?panel=run&job=abc');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateSearchParams({ job: null });
      });

      expect(result.current.params.panel).toBe('run');
      expect(result.current.params.job).toBeUndefined();
      expect(window.location.search).toBe('?panel=run');
    });

    test('updates multiple params at once', () => {
      history.replaceState({}, '', '/workflow?panel=run');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateSearchParams({ job: 'abc', step: '5' });
      });

      expect(result.current.params.panel).toBe('run');
      expect(result.current.params.job).toBe('abc');
      expect(result.current.params.step).toBe('5');
    });

    test('preserves hash when updating search params', () => {
      history.replaceState({}, '', '/workflow?panel=run#step-2');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateSearchParams({ job: 'abc' });
      });

      expect(result.current.params.job).toBe('abc');
      expect(result.current.hash).toBe('step-2');
      expect(window.location.hash).toBe('#step-2');
    });

    test('coerces number values to strings', () => {
      history.replaceState({}, '', '/workflow');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateSearchParams({ page: 42, limit: 100 });
      });

      expect(result.current.params.page).toBe('42');
      expect(result.current.params.limit).toBe('100');
      expect(window.location.search).toBe('?page=42&limit=100');
    });

    test('coerces boolean values to strings', () => {
      history.replaceState({}, '', '/workflow');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateSearchParams({
          active: true,
          archived: false,
        });
      });

      expect(result.current.params.active).toBe('true');
      expect(result.current.params.archived).toBe('false');
      expect(window.location.search).toBe('?active=true&archived=false');
    });

    test('handles mixed types (string, number, boolean, null)', () => {
      history.replaceState({}, '', '/workflow?old=value&remove=me');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateSearchParams({
          panel: 'run',
          page: 5,
          active: true,
          remove: null,
        });
      });

      expect(result.current.params.panel).toBe('run');
      expect(result.current.params.page).toBe('5');
      expect(result.current.params.active).toBe('true');
      expect(result.current.params.old).toBe('value');
      expect(result.current.params.remove).toBeUndefined();
    });
  });

  describe('replaceSearchParams', () => {
    test('replaces all params with new ones (clears unspecified params)', () => {
      history.replaceState({}, '', '/workflow?panel=run&job=abc&step=5');

      const { result } = renderHook(() => useURLState());

      expect(result.current.params.panel).toBe('run');
      expect(result.current.params.job).toBe('abc');
      expect(result.current.params.step).toBe('5');

      act(() => {
        result.current.replaceSearchParams({ panel: 'inspector' });
      });

      // Only panel remains, job and step are cleared
      expect(result.current.params.panel).toBe('inspector');
      expect(result.current.params.job).toBeUndefined();
      expect(result.current.params.step).toBeUndefined();
      expect(window.location.search).toBe('?panel=inspector');
    });

    test('clears all params when given empty object', () => {
      history.replaceState({}, '', '/workflow?panel=run&job=abc');

      const { result } = renderHook(() => useURLState());

      expect(result.current.params.panel).toBe('run');
      expect(result.current.params.job).toBe('abc');

      act(() => {
        result.current.replaceSearchParams({});
      });

      expect(result.current.params).toEqual({});
      expect(window.location.search).toBe('');
    });

    test('does not set params with null values', () => {
      history.replaceState({}, '', '/workflow?panel=run');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.replaceSearchParams({
          job: 'abc',
          step: null,
        });
      });

      expect(result.current.params.job).toBe('abc');
      expect(result.current.params.step).toBeUndefined();
      expect(window.location.search).toBe('?job=abc');
    });

    test('preserves hash when replacing params', () => {
      history.replaceState({}, '', '/workflow?panel=run&job=abc#step-2');

      const { result } = renderHook(() => useURLState());

      expect(result.current.hash).toBe('step-2');

      act(() => {
        result.current.replaceSearchParams({ panel: 'inspector' });
      });

      expect(result.current.params.panel).toBe('inspector');
      expect(result.current.params.job).toBeUndefined();
      expect(result.current.hash).toBe('step-2');
      expect(window.location.hash).toBe('#step-2');
    });

    test('sets multiple params at once (replacing all existing)', () => {
      history.replaceState({}, '', '/workflow?old=value');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.replaceSearchParams({
          panel: 'run',
          job: 'xyz',
          step: '3',
        });
      });

      expect(result.current.params.old).toBeUndefined();
      expect(result.current.params.panel).toBe('run');
      expect(result.current.params.job).toBe('xyz');
      expect(result.current.params.step).toBe('3');
    });

    test('handles special characters in param values', () => {
      history.replaceState({}, '', '/workflow?old=value');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.replaceSearchParams({
          query: 'hello world & stuff',
        });
      });

      expect(result.current.params.old).toBeUndefined();
      expect(result.current.params.query).toBe('hello world & stuff');
    });

    test('coerces number values to strings', () => {
      history.replaceState({}, '', '/workflow?old=value');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.replaceSearchParams({
          page: 1,
          limit: 50,
        });
      });

      expect(result.current.params.old).toBeUndefined();
      expect(result.current.params.page).toBe('1');
      expect(result.current.params.limit).toBe('50');
      expect(window.location.search).toBe('?page=1&limit=50');
    });

    test('coerces boolean values to strings', () => {
      history.replaceState({}, '', '/workflow?old=value');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.replaceSearchParams({
          enabled: true,
          disabled: false,
        });
      });

      expect(result.current.params.old).toBeUndefined();
      expect(result.current.params.enabled).toBe('true');
      expect(result.current.params.disabled).toBe('false');
      expect(window.location.search).toBe('?enabled=true&disabled=false');
    });

    test('handles mixed types with replaceSearchParams', () => {
      history.replaceState({}, '', '/workflow?old=value');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.replaceSearchParams({
          panel: 'inspector',
          page: 3,
          active: true,
          skip: null,
        });
      });

      expect(result.current.params.old).toBeUndefined();
      expect(result.current.params.panel).toBe('inspector');
      expect(result.current.params.page).toBe('3');
      expect(result.current.params.active).toBe('true');
      expect(result.current.params.skip).toBeUndefined();
    });
  });

  describe('updateHash', () => {
    test('adds hash to URL', () => {
      history.replaceState({}, '', '/workflow');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateHash('step-5');
      });

      expect(result.current.hash).toBe('step-5');
      expect(window.location.hash).toBe('#step-5');
    });

    test('updates existing hash in URL', () => {
      history.replaceState({}, '', '/workflow#step-2');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateHash('step-7');
      });

      expect(result.current.hash).toBe('step-7');
      expect(window.location.hash).toBe('#step-7');
    });

    test('removes hash when value is null', () => {
      history.replaceState({}, '', '/workflow#step-2');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateHash(null);
      });

      expect(result.current.hash).toBe('');
      expect(window.location.hash).toBe('');
    });

    test('preserves search params when updating hash', () => {
      history.replaceState({}, '', '/workflow?panel=run&job=abc');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateHash('step-3');
      });

      expect(result.current.params.panel).toBe('run');
      expect(result.current.params.job).toBe('abc');
      expect(result.current.hash).toBe('step-3');
    });
  });

  // ==========================================================================
  // Reactivity - Hook Re-renders
  // ==========================================================================

  describe('reactivity - hook updates', () => {
    test('re-renders when updateSearchParams is called', () => {
      history.replaceState({}, '', '/workflow');

      const { result } = renderHook(() => useURLState());

      // Track renders by checking current value
      const initialParams = result.current.params;

      act(() => {
        result.current.updateSearchParams({ panel: 'run' });
      });

      // Verify state changed (which implies a re-render occurred)
      expect(result.current.params).not.toBe(initialParams);
      expect(result.current.params.panel).toBe('run');
    });

    test('re-renders when updateHash is called', () => {
      history.replaceState({}, '', '/workflow');

      const { result } = renderHook(() => useURLState());
      const initialHash = result.current.hash;

      act(() => {
        result.current.updateHash('step-5');
      });

      expect(result.current.hash).not.toBe(initialHash);
      expect(result.current.hash).toBe('step-5');
    });
  });

  // ==========================================================================
  // Reactivity - External History API Calls
  // ==========================================================================

  describe('reactivity - external history API detection', () => {
    test('detects external history.pushState calls', () => {
      history.replaceState({}, '', '/workflow');

      const { result } = renderHook(() => useURLState());

      expect(result.current.params.panel).toBeUndefined();

      // Simulate external code calling history.pushState
      act(() => {
        history.pushState({}, '', '/workflow?panel=run');
      });

      expect(result.current.params.panel).toBe('run');
    });

    test('detects external history.replaceState calls', () => {
      history.replaceState({}, '', '/workflow?panel=run');

      const { result } = renderHook(() => useURLState());

      expect(result.current.params.panel).toBe('run');

      // Simulate external code calling history.replaceState
      act(() => {
        history.replaceState({}, '', '/workflow?panel=inspector');
      });

      expect(result.current.params.panel).toBe('inspector');
    });

    test('detects hash changes via history.pushState', () => {
      history.replaceState({}, '', '/workflow');

      const { result } = renderHook(() => useURLState());

      expect(result.current.hash).toBe('');

      act(() => {
        history.pushState({}, '', '/workflow#step-3');
      });

      expect(result.current.hash).toBe('step-3');
    });
  });

  describe('reactivity - browser navigation events', () => {
    test('detects browser back/forward navigation (popstate)', () => {
      // Setup initial state
      history.replaceState({}, '', '/workflow?panel=run');

      const { result } = renderHook(() => useURLState());

      expect(result.current.params.panel).toBe('run');

      // Simulate browser navigation changing the URL
      // In a test environment, we manually update location and dispatch popstate
      act(() => {
        history.replaceState({}, '', '/workflow?panel=inspector');
        window.dispatchEvent(new PopStateEvent('popstate', { state: {} }));
      });

      expect(result.current.params.panel).toBe('inspector');

      // Simulate going back
      act(() => {
        history.replaceState({}, '', '/workflow?panel=run');
        window.dispatchEvent(new PopStateEvent('popstate', { state: {} }));
      });

      expect(result.current.params.panel).toBe('run');
    });

    test('detects hashchange events', () => {
      history.replaceState({}, '', '/workflow');

      const { result } = renderHook(() => useURLState());

      expect(result.current.hash).toBe('');

      act(() => {
        // Update location and dispatch hashchange event
        history.replaceState({}, '', '/workflow#step-5');
        window.dispatchEvent(
          new HashChangeEvent('hashchange', {
            oldURL: 'http://localhost/workflow',
            newURL: 'http://localhost/workflow#step-5',
          })
        );
      });

      expect(result.current.hash).toBe('step-5');
    });
  });

  // ==========================================================================
  // Singleton Behavior
  // ==========================================================================

  describe('singleton behavior', () => {
    test('multiple hook instances share the same state', () => {
      history.replaceState({}, '', '/workflow?panel=run&job=abc');

      const { result: result1 } = renderHook(() => useURLState());
      const { result: result2 } = renderHook(() => useURLState());

      // Both instances should see the same state
      expect(result1.current.params.panel).toBe('run');
      expect(result2.current.params.job).toBe('abc');
      expect(result2.current.params.panel).toBe('run');
      expect(result2.current.params.job).toBe('abc');
    });

    test('updates from one instance are visible to other instances', () => {
      history.replaceState({}, '', '/workflow?panel=run');

      const { result: result1 } = renderHook(() => useURLState());
      const { result: result2 } = renderHook(() => useURLState());

      expect(result1.current.params.panel).toBe('run');
      expect(result2.current.params.panel).toBe('run');

      // Update via first instance
      act(() => {
        result1.current.updateSearchParams({ job: 'xyz' });
      });

      // Both instances should see the update
      expect(result1.current.params.job).toBe('xyz');
      expect(result2.current.params.job).toBe('xyz');
    });

    test('hash updates from one instance are visible to others', () => {
      history.replaceState({}, '', '/workflow');

      const { result: result1 } = renderHook(() => useURLState());
      const { result: result2 } = renderHook(() => useURLState());

      expect(result1.current.hash).toBe('');
      expect(result2.current.hash).toBe('');

      act(() => {
        result1.current.updateHash('step-7');
      });

      expect(result1.current.hash).toBe('step-7');
      expect(result2.current.hash).toBe('step-7');
    });
  });

  // ==========================================================================
  // Reference Stability with Immer
  // ==========================================================================

  describe('reference stability with Immer', () => {
    test('changing one param only changes params reference, not unchanged values', () => {
      // This tests the FIXED behavior with Immer structural sharing
      // Now using Record<string, string> with Immer, unchanged params have stable references

      history.replaceState({}, '', '/workflow?panel=run&job=abc');

      const { result } = renderHook(() => useURLState());

      // Capture initial references
      const initialParams = result.current.params;

      // Change ONLY the job parameter
      act(() => {
        result.current.updateSearchParams({ job: 'xyz' });
      });

      // With Immer structural sharing: params object reference changes
      expect(result.current.params).not.toBe(initialParams);

      // But the values are correct
      expect(result.current.params.panel).toBe('run');
      expect(result.current.params.job).toBe('xyz');
    });

    test('updating hash does not change params reference when params unchanged', () => {
      history.replaceState({}, '', '/workflow?panel=run&job=abc');

      const { result } = renderHook(() => useURLState());

      const initialParams = result.current.params;

      // Change ONLY the hash (not search params)
      act(() => {
        result.current.updateHash('step-5');
      });

      // With Immer: params reference should stay stable since params didn't change
      expect(result.current.params).toBe(initialParams);

      // Values are still correct
      expect(result.current.params.panel).toBe('run');
      expect(result.current.params.job).toBe('abc');
      expect(result.current.hash).toBe('step-5');
    });

    test('external history changes create new params reference', () => {
      // When external code changes the URL, we create new state objects
      // This is expected and necessary

      history.replaceState({}, '', '/workflow?panel=run');

      const { result } = renderHook(() => useURLState());

      const initialParams = result.current.params;
      const initialHash = result.current.hash;

      // External code changes URL
      act(() => {
        history.pushState({}, '', '/workflow?panel=run&job=abc');
      });

      // Params reference changes (new param added)
      expect(result.current.params).not.toBe(initialParams);
      // Hash stays the same (both empty strings)
      expect(result.current.hash).toBe(initialHash);
    });
  });

  // ==========================================================================
  // Edge Cases
  // ==========================================================================

  describe('edge cases', () => {
    test('handles special characters in param values', () => {
      history.replaceState({}, '', '/workflow');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateSearchParams({ query: 'hello world & stuff' });
      });

      expect(result.current.params.query).toBe('hello world & stuff');
    });

    test('handles special characters in hash', () => {
      history.replaceState({}, '', '/workflow');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateHash('step-5-with-dashes');
      });

      expect(result.current.hash).toBe('step-5-with-dashes');
    });

    test('handles empty string hash (different from null)', () => {
      history.replaceState({}, '', '/workflow#existing');

      const { result } = renderHook(() => useURLState());

      expect(result.current.hash).toBe('existing');

      // Empty string should remove hash (same as null)
      act(() => {
        result.current.updateHash('');
      });

      expect(result.current.hash).toBe('');
      expect(window.location.hash).toBe('');
    });

    test('handles param with empty string value', () => {
      history.replaceState({}, '', '/workflow');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateSearchParams({ panel: '' });
      });

      // URLSearchParams treats empty string as a valid value
      expect(result.current.params.panel).toBe('');
      expect(window.location.search).toBe('?panel=');
    });

    test('preserves pathname when updating params and hash', () => {
      history.replaceState({}, '', '/workflow/123/edit');

      const { result } = renderHook(() => useURLState());

      act(() => {
        result.current.updateSearchParams({ panel: 'run' });
      });

      expect(window.location.pathname).toBe('/workflow/123/edit');

      act(() => {
        result.current.updateHash('step-5');
      });

      expect(window.location.pathname).toBe('/workflow/123/edit');
    });
  });
});
