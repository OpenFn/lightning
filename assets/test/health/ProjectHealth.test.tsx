import { render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { ProjectHealthContent } from '#/health/ProjectHealth';

const PROJECT_ID = 'f4a1d6c2-0000-4000-8000-000000000001';

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

/** Serves `body`, or fails with a 500 when it is null. */
function stubFetch(body: unknown) {
  const fetchMock = vi.fn(() =>
    Promise.resolve({
      ok: body !== null,
      status: body === null ? 500 : 200,
      json: () => Promise.resolve(body),
    } as Response)
  );

  vi.stubGlobal('fetch', fetchMock);

  return fetchMock;
}

const renderPage = () =>
  render(
    <ProjectHealthContent projectId={PROJECT_ID} projectName="Chad HIV" />
  );

describe('ProjectHealth', () => {
  beforeEach(() => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  test('asks the project endpoint, not a workflow one', async () => {
    const fetchMock = stubFetch(outcomes);

    renderPage();
    await screen.findByText(/work orders/);

    expect(fetchMock).toHaveBeenCalledWith(
      `/api/projects/${PROJECT_ID}/health/outcomes`,
      expect.anything()
    );
  });

  test('shows the project name and totals every final state', async () => {
    stubFetch(outcomes);

    renderPage();

    expect(
      await screen.findByRole('heading', { name: 'Chad HIV' })
    ).toBeVisible();
    // Every final state summed, not just the failures.
    expect(screen.getByText('Last 30 days · 1,287 work orders')).toBeVisible();
  });

  test('shows an error instead of a silently missing subtitle', async () => {
    stubFetch(null);

    renderPage();

    expect(
      await screen.findByText('Could not load stats. Refresh to try again.')
    ).toBeVisible();
  });
});
