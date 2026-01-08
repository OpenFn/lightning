/**
 * # Store Common Utilities
 *
 * Shared utilities for implementing useSyncExternalStore + Immer pattern
 * across different stores in the collaborative editor.
 */

import { produce } from 'immer';
import { useRef, useEffect } from 'react';

/**
 * Creates a withSelector function for a given store's getSnapshot function.
 *
 * This utility creates memoized selectors for referential stability,
 * optimizing React re-renders by only recomputing when state references change.
 *
 * @param getSnapshot - Function that returns the current state snapshot
 * @returns A withSelector function that can create memoized selectors
 *
 * @example
 * ```typescript
 * const withSelector = createWithSelector(getSnapshot);
 *
 * // Create a memoized selector
 * const selectJobs = withSelector((state) => state.jobs);
 *
 * // Use in React component
 * const jobs = useSyncExternalStore(subscribe, selectJobs);
 * ```
 */
export const createWithSelector = <TState>(getSnapshot: () => TState) => {
  return <TResult>(selector: (state: TState) => TResult) => {
    let lastResult: TResult | undefined;
    let lastState: TState | undefined;

    return (): TResult => {
      const currentState = getSnapshot();

      // Only recompute if state reference actually changed
      if (currentState !== lastState) {
        const newResult = selector(currentState);

        // Always update result when state changes (Immer guarantees stable references)
        lastResult = newResult;
        lastState = currentState;
      }

      return lastResult as TResult;
    };
  };
};

/**
 * Type helper for withSelector function signature
 */
export type WithSelector<TState> = <TResult>(
  selector: (state: TState) => TResult
) => () => TResult;
