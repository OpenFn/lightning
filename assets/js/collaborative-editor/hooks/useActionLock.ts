import { useCallback, useRef, useState } from 'react';

/**
 * Guards an async action against re-entrant calls: `run` invokes `fn` unless a
 * previous invocation is still in flight, and `isPending` mirrors the in-flight
 * state for disabling UI. `fn` is expected to handle its own errors; rejections
 * pass through to the caller, and the lock is always released.
 *
 * Not for locks that outlive the promise (e.g. useRunRetry's
 * WebSocket-confirmed submit) — this releases when `fn` settles.
 */
export function useActionLock<A extends unknown[], T = void>(
  fn: (...args: A) => Promise<T>
): { run: (...args: A) => Promise<T | undefined>; isPending: boolean } {
  const fnRef = useRef(fn);
  fnRef.current = fn;

  const pendingRef = useRef(false);
  const [isPending, setIsPending] = useState(false);

  const run = useCallback(async (...args: A): Promise<T | undefined> => {
    if (pendingRef.current) return undefined;
    pendingRef.current = true;
    setIsPending(true);
    try {
      return await fnRef.current(...args);
    } finally {
      pendingRef.current = false;
      setIsPending(false);
    }
  }, []);

  return { run, isPending };
}
