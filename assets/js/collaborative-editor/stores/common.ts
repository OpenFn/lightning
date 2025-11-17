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

/**
 * Hook that watches specified fields on an object and triggers a callback when they change.
 * Similar to useEffect but specifically for tracking field changes on objects.
 *
 * @template T The object type to watch
 * @template K The keys to watch (inferred from watchedKeys)
 * @param currentObject The current object instance to watch
 * @param callback Function called with changed fields when any watched field changes
 * @param watchedKeys Array of keys to watch for changes
 *
 * @example
 * // Watch specific job fields - changedFields will only have 'name' and 'enabled' keys
 * useWatchFields(
 *   currentJob,
 *   (changedFields) => {
 *     if (changedFields.name) console.log("Job name changed:", changedFields.name);
 *     if (changedFields.enabled) console.log("Job enabled changed:", changedFields.enabled);
 *     // changedFields.otherField; // TypeScript error - not in watched keys
 *   },
 *   ["name", "enabled"] as const
 * );
 */
export const useWatchFields = <
  T extends Record<string, unknown>,
  K extends keyof T,
>(
  currentObject: T | null,
  callback: (changedFields: Partial<Pick<T, K>>) => void,
  watchedKeys: readonly K[]
) => {
  const previousObjectRef = useRef<T | null>(null);

  useEffect(() => {
    const previous = previousObjectRef.current;
    const current = currentObject;

    if (!current || !previous) {
      if (current) {
        previousObjectRef.current = produce(current, () => {});
      }
      return;
    }

    const changedFields: Partial<Pick<T, K>> = {};

    watchedKeys.forEach(key => {
      if (previous[key] !== current[key]) {
        changedFields[key] = current[key];
      }
    });

    if (Object.keys(changedFields).length > 0) {
      callback(changedFields);
    }

    previousObjectRef.current = produce(current, () => {});
  }, [currentObject, callback, watchedKeys]);
};
