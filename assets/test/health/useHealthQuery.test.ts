import { act, renderHook } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { useHealthQuery } from '#/health/useHealthQuery';

const URL_7 = '/api/projects/p1/workflows/wf-1/health/outcomes?days=7';
const URL_30 = '/api/projects/p1/workflows/wf-1/health/outcomes?days=30';
const ERROR = 'Could not load workflow stats. Refresh to try again.';

/**
 * Stubs `fetch` with one reply per call, read when the call is made: a body
 * to serve, a number to fail with that status, or a pending promise for a
 * request that never lands.
 */
function stubFetch(initial: unknown) {
  const reply = { next: initial };
  const signals: AbortSignal[] = [];

  const fetchMock = vi.fn((_url: string, init?: RequestInit) => {
    if (init?.signal) signals.push(init.signal);
    const body = reply.next;
    if (typeof body === 'number')
      return Promise.resolve({ ok: false, status: body } as Response);
    return Promise.resolve({
      ok: true,
      status: 200,
      json: () => Promise.resolve(body),
    } as Response);
  });

  vi.stubGlobal('fetch', fetchMock);
  return { fetchMock, signals, reply };
}

const mount = (url = URL_7) =>
  renderHook(({ url }) => useHealthQuery<unknown>(url), {
    initialProps: { url },
  });

// Lets the stubbed replies land. `waitFor` can't: it re-checks on the
// `setInterval` these tests fake.
const settle = () =>
  act(() => new Promise<void>(resolve => setTimeout(resolve, 0)));

const tick = (ms: number) =>
  act(async () => {
    await vi.advanceTimersByTimeAsync(ms);
  });

beforeEach(() => {
  // The hook logs every failed request; the failure tests are deliberate.
  vi.spyOn(console, 'error').mockImplementation(() => {});
  // Only the interval fns, so Testing Library's waiting still runs.
  vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval'] });
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('useHealthQuery', () => {
  // Nothing server-side records a reader's timezone, so the request has to
  // carry it or the chart's buckets are cut on UTC.
  test("sends the reader's timezone with the session cookie", () => {
    const { fetchMock } = stubFetch({ n: 1 });
    mount();

    expect(fetchMock).toHaveBeenCalledWith(
      URL_7,
      expect.objectContaining({
        credentials: 'same-origin',
        headers: {
          'x-timezone': Intl.DateTimeFormat().resolvedOptions().timeZone,
        },
      })
    );
  });

  test('polls every 30 seconds while the tab is visible, and stops while hidden', async () => {
    const { fetchMock, reply } = stubFetch({ n: 1 });
    const { result } = mount();
    await settle();
    expect(result.current.data).toEqual({ n: 1 });

    reply.next = { n: 2 };
    await tick(30_000);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    await settle();
    expect(result.current.data).toEqual({ n: 2 });

    // The interval still fires; the read is gated on visibility.
    vi.spyOn(document, 'hidden', 'get').mockReturnValue(true);
    await tick(30_000);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  // On purpose, and not something to throttle back to the interval: someone
  // looking away and back wants what is true now.
  test('reads again on returning to the tab, without waiting for the tick', async () => {
    const { fetchMock } = stubFetch({ n: 1 });
    const { result } = mount();
    await settle();
    expect(result.current.data).toEqual({ n: 1 });

    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  test('lets a read slower than the interval finish, then waits a whole interval', async () => {
    let land!: (body: unknown) => void;
    const { fetchMock, reply } = stubFetch(
      new Promise(resolve => {
        land = resolve;
      })
    );
    const { result } = mount();

    // A tick here would abort the read it is waiting on.
    await tick(95_000);
    expect(fetchMock).toHaveBeenCalledTimes(1);

    reply.next = { n: 2 };
    land({ n: 1 });
    await settle();
    expect(result.current.data).toEqual({ n: 1 });

    // Measured from the answer, not the request.
    await tick(29_000);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    await tick(1_000);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  test('keeps the last answer when a poll fails, and recovers on the next', async () => {
    const { reply } = stubFetch({ n: 1 });
    const { result } = mount();
    await settle();
    expect(result.current.data).toEqual({ n: 1 });

    reply.next = 502;
    await tick(30_000);
    expect(result.current).toEqual({ data: { n: 1 }, error: null });

    reply.next = { n: 2 };
    await tick(30_000);
    await settle();
    expect(result.current.data).toEqual({ n: 2 });
  });

  test('aborts its request on unmount', () => {
    const { signals } = stubFetch(new Promise(() => {}));
    const { unmount } = mount();

    expect(signals[0]?.aborted).toBe(false);
    unmount();
    expect(signals[0]?.aborted).toBe(true);
  });

  // The opposite of a poll: a new range is a new question, so the last answer
  // goes, or a panel would show one window's numbers under another's label.
  test('drops the last answer when the url changes', async () => {
    const { reply } = stubFetch({ n: 1 });
    const { result, rerender } = mount();
    await settle();
    expect(result.current.data).toEqual({ n: 1 });

    reply.next = new Promise(() => {});
    rerender({ url: URL_30 });
    expect(result.current).toEqual({ data: null, error: null });
  });

  test('reports a failed load for a new url with no stale numbers', async () => {
    const { reply } = stubFetch({ n: 1 });
    const { result, rerender } = mount();
    await settle();
    expect(result.current.data).toEqual({ n: 1 });

    reply.next = 500;
    rerender({ url: URL_30 });
    await settle();
    expect(result.current).toEqual({ data: null, error: ERROR });
  });
});
