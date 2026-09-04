import { render, screen } from '@testing-library/react';
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

const ERROR = 'Could not load stats. Refresh to try again.';

/**
 * Stubs `fetch`, keyed by the last path segment, so a test can pick which
 * slice fails. A value is a body to serve; a number is the status to fail
 * with — the panels degrade independently and the tests have to say so.
 */
function stubFetch(responses: Record<string, unknown>) {
  const signals: AbortSignal[] = [];

  const fetchMock = vi.fn((url: string, init?: RequestInit) => {
    if (init?.signal) signals.push(init.signal);

    const slice = url.split('/').pop() ?? '';
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
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('WorkflowHealth', () => {
  test('requests each slice from the project-scoped health path', async () => {
    const { fetchMock } = mount(both);

    await screen.findByText('Success');

    expect(fetchMock).toHaveBeenCalledWith(
      '/api/projects/proj-1/workflows/wf-1/health/outcomes',
      expect.objectContaining({ credentials: 'same-origin' })
    );
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/projects/proj-1/workflows/wf-1/health/failures',
      expect.objectContaining({ credentials: 'same-origin' })
    );
  });

  test('renders the header, deriving the day count from the window', async () => {
    mount(both);

    expect(
      await screen.findByRole('heading', { name: 'Sync patients' })
    ).toBeInTheDocument();
    expect(screen.getByText('Last 30 days · 1,287 work orders')).toBeVisible();
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

  test('stops showing the old numbers once the request changes', async () => {
    const { rerender } = mount(both);

    await screen.findByText('Success');

    rerender(
      <HealthContent
        workflowId="wf-2"
        projectId="proj-1"
        workflowName="Sync households"
      />
    );

    expect(screen.queryAllByText('Loading…')).toHaveLength(3);
  });
});
