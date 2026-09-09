import { act, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { HealthContent } from '#/health/WorkflowHealth';

const outcomes = {
  window: { from: '2026-08-01T10:00:00Z', to: '2026-08-31T10:00:00Z' },
  counts: {
    success: 1146,
    failed: 98,
    crashed: 24,
    cancelled: 0,
    killed: 12,
    exception: 0,
    lost: 7,
    rejected: 0,
  },
};

const failureSignatures = {
  window: outcomes.window,
  signatures: [
    {
      count: 98,
      exit_reason: 'fail',
      error_type: 'RuntimeError',
      step_name: 'Map-beneficiary',
      adaptor: '@openfn/language-common@2.0.0',
    },
  ],
};

const both = { outcomes, failures: failureSignatures };

const ERROR = 'Could not load workflow stats. Refresh to try again.';

/**
 * Stubs `fetch`, keyed by the last path segment, so a test can pick which
 * slice fails. A value is a body to serve; a number is the status to fail
 * with — the panels degrade independently and the tests have to say so. A
 * pending promise as the body is a request that never lands.
 */
function stubFetch(responses: Record<string, unknown>) {
  const signals: AbortSignal[] = [];

  const fetchMock = vi.fn((url: string, init?: RequestInit) => {
    if (init?.signal) signals.push(init.signal);

    const slice = url.split('?')[0].split('/').pop() ?? '';
    const response = responses[slice];

    if (typeof response === 'number' || response === undefined) {
      return Promise.resolve({
        ok: false,
        status: typeof response === 'number' ? response : 404,
      } as Response);
    }

    return Promise.resolve({
      ok: true,
      status: 200,
      json: () => Promise.resolve(response),
    } as Response);
  });

  vi.stubGlobal('fetch', fetchMock);

  return { fetchMock, signals };
}

function mount(responses: Record<string, unknown>) {
  const stub = stubFetch(responses);

  const rendered = render(
    <HealthContent
      workflowId="wf-1"
      projectId="proj-1"
      workflowName="Sync patients"
    />
  );

  return { ...rendered, ...stub };
}

beforeEach(() => {
  // The hook logs every failed request; the failure tests are deliberate.
  vi.spyOn(console, 'error').mockImplementation(() => {});
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('WorkflowHealth', () => {
  test('requests each slice from the project-scoped health path', async () => {
    const { fetchMock } = mount(both);

    await screen.findByText('Success');

    expect(fetchMock).toHaveBeenCalledWith(
      '/api/projects/proj-1/workflows/wf-1/health/outcomes?days=30',
      expect.objectContaining({ credentials: 'same-origin' })
    );
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/projects/proj-1/workflows/wf-1/health/failures?days=30',
      expect.objectContaining({ credentials: 'same-origin' })
    );
  });

  test('moves the updated clock when the numbers arrive', async () => {
    mount(both);

    expect(
      await screen.findByText(
        `Last Updated ${new Date(outcomes.window.to).toLocaleTimeString()}`
      )
    ).toBeVisible();
  });

  test('polls every 30 seconds while the tab is visible, and stops while hidden', async () => {
    // Mutable so the polled request can answer differently.
    const responses: Record<string, unknown> = { ...both };

    // Only the interval fns: Testing Library's waiting runs on real
    // `setTimeout`, so the first load below can still be awaited.
    vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval'] });

    const { fetchMock } = mount(responses);

    await screen.findByText('Last 30 days · 1,287 work orders');
    expect(fetchMock).toHaveBeenCalledTimes(2);

    responses.outcomes = {
      ...outcomes,
      counts: { ...outcomes.counts, success: 2146 },
    };

    await act(async () => {
      await vi.advanceTimersByTimeAsync(30_000);
    });
    expect(fetchMock).toHaveBeenCalledTimes(4);

    expect(
      await screen.findByText('Last 30 days · 2,287 work orders')
    ).toBeVisible();

    // The interval still fires; the bump is gated on visibility.
    vi.spyOn(document, 'hidden', 'get').mockReturnValue(true);
    document.dispatchEvent(new Event('visibilitychange'));

    await act(async () => {
      await vi.advanceTimersByTimeAsync(30_000);
    });
    expect(fetchMock).toHaveBeenCalledTimes(4);
  });

  test('reads again on returning to the tab, without waiting for the tick', async () => {
    vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval'] });

    const { fetchMock } = mount({ ...both });

    await screen.findByText('Last 30 days · 1,287 work orders');
    expect(fetchMock).toHaveBeenCalledTimes(2);

    const hidden = vi.spyOn(document, 'hidden', 'get').mockReturnValue(false);

    const visibility = (away: boolean) => {
      hidden.mockReturnValue(away);
      act(() => {
        document.dispatchEvent(new Event('visibilitychange'));
      });
    };

    // On purpose, and not something to throttle back to the interval: someone
    // looking away and back wants what is true now, not what was true up to
    // half a minute ago.
    visibility(true);
    visibility(false);

    expect(fetchMock).toHaveBeenCalledTimes(4);
  });

  test('lets a read slower than the interval finish', async () => {
    let land!: (body: unknown) => void;

    const responses: Record<string, unknown> = {
      ...both,
      outcomes: new Promise(resolve => {
        land = resolve;
      }),
    };

    vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval'] });

    const { fetchMock } = mount(responses);

    const reads = () =>
      fetchMock.mock.calls.filter(([url]) => url.includes('/outcomes')).length;

    // Deliberately off the interval grid: a timer that had been running all
    // along would be due at 120s, a full interval after the answer is 125s.
    await act(async () => {
      await vi.advanceTimersByTimeAsync(95_000);
    });

    // Skipped, not stacked: a tick that fired here would abort the read it is
    // waiting on, and the next one would too.
    expect(reads()).toBe(1);

    land(outcomes);

    expect(
      await screen.findByText('Last 30 days · 1,287 work orders')
    ).toBeVisible();

    // And the gap that follows is a whole interval measured from the answer.
    // On a grid measured from the request, a read this slow would be due again
    // the moment it landed, and a slow endpoint would never get a quiet spell.
    await act(async () => {
      await vi.advanceTimersByTimeAsync(29_000);
    });
    expect(reads()).toBe(1);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(1_000);
    });
    expect(reads()).toBe(2);
  });

  test('keeps the numbers on screen when a poll fails', async () => {
    const responses: Record<string, unknown> = { ...both };

    vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval'] });

    mount(responses);

    await screen.findByText('Last 30 days · 1,287 work orders');

    responses['outcomes'] = 502;
    responses['failures'] = 502;

    await act(async () => {
      await vi.advanceTimersByTimeAsync(30_000);
    });

    expect(screen.queryByRole('alert')).toBeNull();
    expect(screen.getByText('Last 30 days · 1,287 work orders')).toBeVisible();
    expect(screen.getByText('Success')).toBeVisible();

    // And recovers on the tick after, with no reload.
    responses['outcomes'] = {
      ...outcomes,
      counts: { ...outcomes.counts, success: 2146 },
    };

    await act(async () => {
      await vi.advanceTimersByTimeAsync(30_000);
    });

    expect(
      await screen.findByText('Last 30 days · 2,287 work orders')
    ).toBeVisible();
  });

  test('renders the header, deriving the day count from the window', async () => {
    mount(both);

    expect(
      await screen.findByRole('heading', { name: 'Sync patients' })
    ).toBeInTheDocument();
    expect(screen.getByText('Last 30 days · 1,287 work orders')).toBeVisible();
  });

  test('refetches both slices at the selected range', async () => {
    const { fetchMock } = mount(both);

    await screen.findByText('Success');

    await userEvent.click(screen.getByRole('radio', { name: 'Last 7 days' }));

    expect(fetchMock).toHaveBeenCalledWith(
      '/api/projects/proj-1/workflows/wf-1/health/outcomes?days=7',
      expect.objectContaining({ credentials: 'same-origin' })
    );
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/projects/proj-1/workflows/wf-1/health/failures?days=7',
      expect.objectContaining({ credentials: 'same-origin' })
    );
  });

  test('calls a one-day window "Last 24 hours", not "Last 1 day"', async () => {
    const dayWide = {
      ...outcomes,
      window: { from: '2026-08-30T10:00:00Z', to: '2026-08-31T10:00:00Z' },
    };

    mount({ outcomes: dayWide, failures: failureSignatures });

    expect(
      await screen.findByText('Last 24 hours · 1,287 work orders')
    ).toBeVisible();
  });

  test('folds the failure states into the Outcomes donut', async () => {
    mount(both);

    // 98 + 24 + 12 + 7 — one response feeds both donuts, so the two panels can
    // only disagree if this fold drifts from the breakdown's own total.
    expect(await screen.findByText('Failed')).toBeVisible();
    expect(screen.getByText('141')).toBeVisible();
    expect(screen.getByText('Success')).toBeVisible();
  });

  test('breaks the same failures down by work order state', async () => {
    mount(both);

    expect(
      await screen.findByRole('heading', { name: 'Failure breakdown' })
    ).toBeVisible();
    expect(screen.getByText('failed')).toBeVisible();
    expect(screen.getByText('69.5%')).toBeVisible();
    expect(screen.queryByText('cancelled')).not.toBeInTheDocument();
  });

  test('lists the failure signatures in the triage table', async () => {
    mount(both);

    expect(
      await screen.findByRole('heading', { name: 'Triage' })
    ).toBeVisible();
    expect(screen.getByRole('cell', { name: '98' })).toBeVisible();
    expect(
      screen.getByText(
        "Job code hit a value it didn't expect, often a missing input field."
      )
    ).toBeVisible();
  });

  test('reports a refused request without echoing the server', async () => {
    mount({ outcomes: 404, failures: 404 });

    // Both slices refused takes every panel with it.
    expect(await screen.findAllByText(ERROR)).toHaveLength(3);
    expect(screen.queryByText(/404|Not Found/)).toBeNull();
  });

  test('degrades both donuts when the outcomes request fails', async () => {
    mount({ outcomes: 500, failures: failureSignatures });

    // Both donuts read the same response, so both degrade.
    expect(await screen.findAllByText(ERROR)).toHaveLength(2);
  });

  // The whole point of requesting each slice separately: one failing query
  // must not blank the panels that answered.
  test('keeps the donuts when only the triage query fails', async () => {
    mount({ outcomes, failures: 500 });

    expect(await screen.findByText(ERROR)).toBeVisible();
    expect(screen.getByText('Success')).toBeVisible();
    expect(screen.getByText('69.5%')).toBeVisible();
  });

  test('keeps the page around a failed chart', async () => {
    mount({ outcomes: 500, failures: 500 });

    await screen.findAllByText(ERROR);
    expect(
      screen.getByRole('heading', { name: 'Sync patients' })
    ).toBeVisible();
    expect(screen.getByRole('heading', { name: 'Outcomes' })).toBeVisible();
    expect(
      screen.getByRole('heading', { name: 'Failure breakdown' })
    ).toBeVisible();
    expect(screen.getByRole('heading', { name: 'Triage' })).toBeVisible();
  });

  test('aborts in-flight requests on unmount', async () => {
    const { unmount, signals } = mount(both);

    await screen.findByText('Success');

    expect(signals).toHaveLength(2);
    expect(signals.every(signal => signal.aborted)).toBe(false);

    unmount();

    expect(signals.every(signal => signal.aborted)).toBe(true);
  });

  // The opposite of the polling case above, and deliberately so. A
  // tick re-asks the same question, so the last answer holds; a range switch is
  // a new question, so every panel drops its answer at the same moment.
  test('drops every panel on a range switch', async () => {
    const responses: Record<string, unknown> = { ...both };

    mount(responses);

    await screen.findByText('Success');

    // A body that never resolves: the range request stays in flight.
    responses['outcomes'] = new Promise(() => {});
    responses['failures'] = new Promise(() => {});

    await userEvent.click(screen.getByRole('radio', { name: 'Last 7 days' }));

    expect(screen.queryByText('Success')).toBeNull();
    expect(screen.getByRole('status')).toHaveTextContent('Loading…');
  });

  // Why the panels drop together rather than each keeping its own last answer:
  // `outcomes` is a group-by and `failures` a three-way join, so the cheap one
  // lands first. Keeping stale data would put the new window in the subtitle
  // while the Triage card below still named the old one.
  test('never names two windows at once during a range switch', async () => {
    const quiet = { window: outcomes.window, signatures: [] };
    const responses: Record<string, unknown> = { outcomes, failures: quiet };

    mount(responses);

    expect(
      await screen.findByText('No failures in the last 30 days')
    ).toBeVisible();

    // The cheap slice answers the new range; the heavy join never lands.
    responses['outcomes'] = {
      ...outcomes,
      window: { from: '2026-08-24T10:00:00Z', to: '2026-08-31T10:00:00Z' },
    };
    responses['failures'] = new Promise(() => {});

    await userEvent.click(screen.getByRole('radio', { name: 'Last 7 days' }));

    await screen.findByText('Last 7 days · 1,287 work orders');

    expect(screen.queryByText('No failures in the last 30 days')).toBeNull();
  });

  // The one case where the kept numbers are dropped: nothing is coming to
  // replace them, so leaving them up would strand one window's counts under
  // another window's label.
  test('drops the stale numbers when the new request fails', async () => {
    const responses: Record<string, unknown> = { ...both };

    mount(responses);

    await screen.findByText('Success');

    responses['outcomes'] = 500;

    await userEvent.click(screen.getByRole('radio', { name: 'Last 7 days' }));

    // An `alert`, so the failure is read out where the subtitle falls silent.
    const alerts = await screen.findAllByRole('alert');
    expect(alerts.map(alert => alert.textContent)).toEqual([ERROR, ERROR]);
    expect(screen.queryByText('Success')).toBeNull();
  });

  // One announcement for the page, from the subtitle; the cards say it too,
  // but only to a reader who lands inside them. jsdom does no layout, so the
  // reserved height itself can only be checked in a browser.
  test('announces loading once, not once per panel', () => {
    mount(both);

    expect(screen.getByRole('status')).toHaveTextContent('Loading…');
    expect(screen.getAllByText('Loading…')).toHaveLength(4);
  });
});
