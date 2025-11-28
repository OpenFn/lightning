/**
 * Creates a throttled function that only invokes the provided function
 * at most once per specified interval.
 *
 * Features:
 * - Fires immediately on first call (leading edge)
 * - Captures latest arguments during throttle window
 * - Fires once more after interval with latest args (trailing edge)
 *
 * @param fn - The function to throttle
 * @param interval - Minimum time between invocations in milliseconds
 * @returns The throttled function
 */
export default function throttle<T extends unknown[]>(
  fn: (...args: T) => void,
  interval: number
): (...args: T) => void {
  let lastCall = 0;
  let timeoutId: NodeJS.Timeout | undefined;
  let lastArgs: T | undefined;

  return (...args: T) => {
    const now = Date.now();
    lastArgs = args;

    if (now - lastCall >= interval) {
      // Enough time has passed, call immediately
      lastCall = now;
      fn(...args);
    } else if (!timeoutId) {
      // Schedule trailing call to capture final position
      timeoutId = setTimeout(
        () => {
          lastCall = Date.now();
          timeoutId = undefined;
          if (lastArgs) fn(...lastArgs);
        },
        interval - (now - lastCall)
      );
    }
  };
}
