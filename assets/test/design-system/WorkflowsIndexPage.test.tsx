import { act, fireEvent, screen, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import {
  WorkflowsIndexPage,
  type Props,
} from '../../js/design-system/pages/WorkflowsIndexPage';

import { renderIsland } from './renderIsland';

const row = (
  id: string,
  name: string,
  enabled: boolean
): Props['stats'][number] => ({
  workflow: {
    id,
    name,
    updatedAt: '2026-10-01T10:00:00Z',
    enabled,
    triggerType: 'webhook',
  },
  triggerEnabled: enabled,
  state: enabled ? 'live' : 'draft',
  toggleTooltip: enabled
    ? 'This workflow is active (webhook trigger enabled)'
    : 'This workflow is inactive (manual runs only)',
  lastWorkOrder: null,
  lastFailedAt: null,
  workordersCount: 0,
  failedWorkordersCount: 0,
  stepCount: 0,
  stepSuccessRate: 0,
  historyHref: `/projects/p1/history?filters[workflow_id]=${id}`,
  failedHistoryHref: `/projects/p1/history?filters[workflow_id]=${id}`,
});

const props: Props = {
  project: { id: 'p1', parentId: null, color: null },
  projectLabel: 'Malawi HIV',
  period: 'last 30 days',
  stats: [row('wf-1', 'Intake', true), row('wf-2', 'Weekly report', false)],
  metrics: {
    workOrders: { total: 0, pending: 0, failed: 0, failedPercentage: 0 },
    runs: { total: 0, pending: 0, success: 0, successRate: 0 },
  },
  pendingHref: '/projects/p1/history?filters[pending]=true',
  failedHref: '/projects/p1/history?filters[failed]=true',
  searchTerm: '',
  sort: { key: 'name', direction: 'asc' },
  canCreateWorkflow: true,
  canDeleteWorkflow: true,
  lifecycle: false,
};

const renderPage = (overrides: Partial<Props> = {}) => {
  const { pushEvent, navigate, redirect, setProps } = renderIsland<Props>(
    WorkflowsIndexPage,
    { ...props, ...overrides }
  );
  // The LiveView's next props, as a patch would bring them.
  const patch = (next: Partial<Props>) => setProps({ ...props, ...next });
  return { pushEvent, navigate, redirect, patch };
};

const deferred = () => {
  let resolve!: (value: unknown) => void;
  const promise = new Promise(_resolve => {
    resolve = _resolve;
  });
  return { promise, resolve };
};

const rowOf = (name: string) => screen.getByText(name).closest('tr')!;

describe('WorkflowsIndexPage', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  test('searches 300 ms after the last keystroke and clears at once', () => {
    const { pushEvent } = renderPage();
    const box = screen.getByPlaceholderText('Search');
    fireEvent.change(box, { target: { value: 'syn' } });
    fireEvent.change(box, { target: { value: 'sync' } });
    expect(pushEvent).not.toHaveBeenCalled();

    vi.advanceTimersByTime(300);

    expect(pushEvent).toHaveBeenCalledTimes(1);
    expect(pushEvent).toHaveBeenCalledWith('search_workflows', {
      value: 'sync',
    });
    expect((box as HTMLInputElement).value).toBe('sync');

    fireEvent.click(document.getElementById('clear_search_button')!);
    expect(pushEvent).toHaveBeenCalledWith('clear_search', {});
  });

  test('a slow reply to an older search never overwrites what was typed', async () => {
    const { pushEvent, patch } = renderPage();
    const first = deferred();
    const second = deferred();
    pushEvent
      .mockReturnValueOnce(first.promise)
      .mockReturnValueOnce(second.promise);
    const box = screen.getByPlaceholderText<HTMLInputElement>('Search');

    fireEvent.change(box, { target: { value: 'sy' } });
    vi.advanceTimersByTime(300);
    fireEvent.change(box, { target: { value: 'syn' } });
    vi.advanceTimersByTime(300);
    expect(pushEvent).toHaveBeenCalledTimes(2);

    // The first search is answered and its URL patched while the second is
    // still out: the box keeps "syn".
    await act(async () => {
      first.resolve({});
      await Promise.resolve();
    });
    patch({ searchTerm: 'sy' });
    expect(box.value).toBe('syn');

    await act(async () => {
      second.resolve({});
      await Promise.resolve();
    });
    patch({ searchTerm: 'syn' });
    expect(box.value).toBe('syn');

    // With nothing pending the box follows the URL (a back navigation).
    patch({ searchTerm: '' });
    expect(box.value).toBe('');
  });

  test('sorts by patching the URL, keeping the search, with the next order in each column link', () => {
    window.history.replaceState(
      null,
      '',
      '/projects/p1/w?q=in&sort=name&dir=asc'
    );
    const { navigate } = renderPage({ searchTerm: 'in' });
    const name = screen.getByRole('link', { name: 'Name' });
    expect(name.getAttribute('href')).toBe(
      '/projects/p1/w?q=in&sort=name&dir=desc'
    );
    expect(
      screen.getByRole('link', { name: 'Work Orders' }).getAttribute('href')
    ).toBe('/projects/p1/w?q=in&sort=workorders_count&dir=asc');

    fireEvent.click(name);

    expect(navigate).toHaveBeenCalledWith(
      '/projects/p1/w?q=in&sort=name&dir=desc',
      { replace: false }
    );
  });

  test('switches and deletes with the payloads the LiveView reads', () => {
    const { pushEvent } = renderPage();
    fireEvent.click(rowOf('Weekly report').querySelector('[role=switch]')!);
    expect(pushEvent).toHaveBeenCalledWith('toggle_workflow_state', {
      workflow_state: 'true',
      value_key: 'wf-2',
    });

    fireEvent.click(
      within(rowOf('Intake')).getByRole('button', { name: 'Delete' })
    );
    fireEvent.click(
      within(screen.getByRole('dialog')).getByRole('button', { name: 'Delete' })
    );
    expect(pushEvent).toHaveBeenCalledWith('delete_workflow', { id: 'wf-1' });
  });

  test('links each row to its editor and health page', () => {
    const { redirect } = renderPage();
    expect(
      rowOf('Intake')
        .querySelector('a[href="/projects/p1/w/wf-1/health"]')
        ?.textContent?.trim()
    ).toBe('Health');

    fireEvent.click(screen.getByText('Intake'));
    expect(redirect).toHaveBeenCalledWith('/projects/p1/w/wf-1', undefined);
  });

  test('a sandbox with the lifecycle on keeps its switches under "Turn on"', () => {
    renderPage({
      lifecycle: true,
      project: { id: 'p1', parentId: 'p0', color: null },
    });
    expect(
      screen.getByRole('columnheader', { name: 'Turn on' })
    ).toBeInTheDocument();
    expect(screen.getAllByRole('switch')).toHaveLength(2);
  });
});
