import { renderHook, act } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';

import { useActionLock } from '#/collaborative-editor/hooks/useActionLock';

function deferred<T>() {
  let deferredResolve!: (value: T) => void;
  let deferredReject!: (reason?: unknown) => void;
  const promise = new Promise<T>((resolve, reject) => {
    deferredResolve = resolve;
    deferredReject = reject;
  });
  return { promise, resolve: deferredResolve, reject: deferredReject };
}

describe('useActionLock', () => {
  it('starts with isPending false', () => {
    const fn = vi.fn(async () => {});
    const { result } = renderHook(() => useActionLock(fn));
    expect(result.current.isPending).toBe(false);
  });

  it('invokes fn and sets isPending while in flight', async () => {
    const { promise, resolve } = deferred<void>();
    const fn = vi.fn(() => promise);
    const { result } = renderHook(() => useActionLock(fn));

    let runPromise!: Promise<void | undefined>;
    act(() => {
      runPromise = result.current.run();
    });

    expect(fn).toHaveBeenCalledTimes(1);
    expect(result.current.isPending).toBe(true);

    await act(async () => {
      resolve();
      await runPromise;
    });

    expect(result.current.isPending).toBe(false);
  });

  it('ignores re-entrant calls while a previous call is in flight', async () => {
    const { promise, resolve } = deferred<void>();
    const fn = vi.fn(() => promise);
    const { result } = renderHook(() => useActionLock(fn));

    let first!: Promise<void | undefined>;
    let second!: Promise<void | undefined>;
    act(() => {
      first = result.current.run();
      second = result.current.run();
    });

    expect(fn).toHaveBeenCalledTimes(1);

    await act(async () => {
      resolve();
      await Promise.all([first, second]);
    });

    expect(await second).toBeUndefined();
  });

  it('allows a new call once the previous one settles', async () => {
    const fn = vi.fn(async () => {});
    const { result } = renderHook(() => useActionLock(fn));

    await act(async () => {
      await result.current.run();
    });
    await act(async () => {
      await result.current.run();
    });

    expect(fn).toHaveBeenCalledTimes(2);
  });

  it('releases the lock and rethrows when fn rejects', async () => {
    const error = new Error('boom');
    const fn = vi.fn().mockRejectedValueOnce(error);
    const { result } = renderHook(() => useActionLock(fn));

    await act(async () => {
      await expect(result.current.run()).rejects.toThrow('boom');
    });

    expect(result.current.isPending).toBe(false);

    fn.mockResolvedValueOnce(undefined);
    await act(async () => {
      await result.current.run();
    });
    expect(fn).toHaveBeenCalledTimes(2);
  });

  it('passes through arguments and resolved value', async () => {
    const fn = vi.fn((a: number, b: number) => Promise.resolve(a + b));
    const { result } = renderHook(() => useActionLock(fn));

    let value: number | undefined;
    await act(async () => {
      value = await result.current.run(2, 3);
    });

    expect(fn).toHaveBeenCalledWith(2, 3);
    expect(value).toBe(5);
  });

  it('uses the latest fn reference without changing run identity', async () => {
    const fnA = vi.fn(() => Promise.resolve('a'));
    const fnB = vi.fn(() => Promise.resolve('b'));
    const { result, rerender } = renderHook(({ fn }) => useActionLock(fn), {
      initialProps: { fn: fnA },
    });

    const runRef = result.current.run;
    rerender({ fn: fnB });
    expect(result.current.run).toBe(runRef);

    let value: string | undefined;
    await act(async () => {
      value = await result.current.run();
    });

    expect(fnA).not.toHaveBeenCalled();
    expect(fnB).toHaveBeenCalledTimes(1);
    expect(value).toBe('b');
  });
});
