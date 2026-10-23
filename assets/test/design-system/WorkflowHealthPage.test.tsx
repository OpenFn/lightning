import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, test, vi } from 'vitest';

import {
  type Props,
  WorkflowHealthPage,
} from '../../js/design-system/pages/WorkflowHealthPage';

import { renderIsland } from './renderIsland';

const props: Props = {
  project: {
    id: 'p1',
    parentId: null,
    color: null,
    historyRetentionPeriod: null,
  },
  projectLabel: 'Malawi HIV',
  workflow: { id: 'wf-1', name: 'Sync patients' },
};

const base = '/api/projects/p1/workflows/wf-1/health';
const span = { from: '2026-08-01T10:00:00Z', to: '2026-08-31T10:00:00Z' };
const replies: Record<string, unknown> = {
  outcomes: {
    window: span,
    counts: {
      success: 3,
      failed: 1,
      crashed: 0,
      cancelled: 0,
      killed: 0,
      exception: 0,
      lost: 0,
      rejected: 0,
    },
  },
  failures: { window: span, signatures: [] },
  runs: { window: span, timezone: 'UTC', bucket_hours: 12, buckets: [] },
};

const stubFetch = () => {
  const fetchMock = vi.fn((url: string) => {
    const [slice = ''] = url.split('/').pop()!.split('?');
    return Promise.resolve(Response.json(replies[slice]));
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
};

const asked = (fetchMock: ReturnType<typeof stubFetch>) =>
  fetchMock.mock.calls.map(([url]) => url);

describe('WorkflowHealthPage', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  test('asks the three health endpoints for the last 7 days, then again for a new range', async () => {
    const fetchMock = stubFetch();
    renderIsland<Props>(WorkflowHealthPage, props);

    await waitFor(() =>
      expect(asked(fetchMock)).toEqual([
        `${base}/outcomes?days=7`,
        `${base}/failures?days=7`,
        `${base}/runs?days=7`,
      ])
    );
    screen.getByRole('heading', { name: 'Sync patients' });

    await userEvent.click(screen.getByRole('radio', { name: 'Last 24 hours' }));
    await waitFor(() =>
      expect(asked(fetchMock).slice(3)).toEqual([
        `${base}/outcomes?days=1`,
        `${base}/failures?days=1`,
        `${base}/runs?days=1`,
      ])
    );
  });

  test('disables ranges longer than the project keeps history for', () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(() => new Promise(() => {}))
    );
    renderIsland<Props>(WorkflowHealthPage, {
      ...props,
      project: { ...props.project, historyRetentionPeriod: 7 },
    });

    expect(screen.getByRole('radio', { name: 'Last 30 days' })).toHaveAttribute(
      'aria-disabled',
      'true'
    );
    expect(
      screen.getByRole('radio', { name: 'Last 7 days' })
    ).not.toHaveAttribute('aria-disabled');
  });
});
