export type DebouncedFunction<T extends unknown[]> = {
  (...args: T): void;
  cancel: () => void;
};

/**
 * Creates a debounced function that delays invoking func until after delay
 * milliseconds have elapsed since the last time the debounced function was invoked.
 *
 * Features:
 * - Promise-aware: Waits for previous invocation to complete before allowing next
 * - Cancellable: Uses AbortController for cancellation
 *
 * @param fn - The function to debounce (receives AbortSignal as first argument)
 * @param delay - The number of milliseconds to delay
 * @returns The debounced function with a cancel method
 */
export default function debounce<T extends unknown[]>(
  fn: (signal: AbortSignal, ...args: T) => void | Promise<void>,
  delay: number
): DebouncedFunction<T> {
  let timeoutId: NodeJS.Timeout | undefined;
  let pendingPromise: Promise<void> | null = null;
  let abortController: AbortController | null = null;

  const debounced = (...args: T) => {
    // Cancel any pending debounce timeout
    clearTimeout(timeoutId);

    // If there's a pending promise, don't start a new timeout
    // (Wait for current operation to complete first)
    if (pendingPromise) {
      return;
    }

    timeoutId = setTimeout(() => {
      void (async () => {
        // Cancel previous abort controller if exists
        if (abortController) {
          abortController.abort();
        }

        abortController = new AbortController();

        try {
          const result = fn(abortController.signal, ...args);
          if (result instanceof Promise) {
            pendingPromise = result;
            await result;
          }
        } catch (err) {
          // Ignore abort errors, re-throw others
          if (err instanceof Error && err.name !== 'AbortError') {
            throw err;
          }
        } finally {
          pendingPromise = null;
          abortController = null;
        }
      })();
    }, delay);
  };

  debounced.cancel = () => {
    clearTimeout(timeoutId);
    timeoutId = undefined;

    if (abortController) {
      abortController.abort();
      abortController = null;
    }

    pendingPromise = null;
  };

  return debounced;
}
