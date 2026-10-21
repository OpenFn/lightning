import { fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { WorkflowsIndexPage } from '../../js/design-system/pages/WorkflowsIndexPage';

const row = (id: string, name: string, enabled: boolean) => ({
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

const props = {
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
  sortKey: 'name',
  sortDirection: 'asc',
  canCreateWorkflow: true,
  canDeleteWorkflow: true,
  lifecycle: false,
};

const renderPage = (overrides: Partial<typeof props> = {}) => {
  const pushEvent = vi.fn().mockResolvedValue({});
  const redirect = vi.fn();
  render(
    <WorkflowsIndexPage
      data-props={JSON.stringify({ ...props, ...overrides })}
      pushEvent={pushEvent}
      handleEvent={vi.fn()}
      navigate={vi.fn()}
      redirect={redirect}
    />
  );
  return { pushEvent, redirect };
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

  test('sorts through the server, with the next order in each column link', () => {
    const { pushEvent } = renderPage();
    const name = screen.getByRole('link', { name: 'Name' });
    expect(name.getAttribute('href')).toBe('/projects/p1/w?sort=name&dir=desc');
    expect(
      screen.getByRole('link', { name: 'Work Orders' }).getAttribute('href')
    ).toBe('/projects/p1/w?sort=workorders_count&dir=asc');

    fireEvent.click(name);

    expect(pushEvent).toHaveBeenCalledWith('sort', { by: 'name' });
  });

  test('switches and deletes with the payloads the LiveView reads', () => {
    const { pushEvent } = renderPage();
    fireEvent.click(rowOf('Weekly report').querySelector('[role=switch]')!);
    expect(pushEvent).toHaveBeenCalledWith('toggle_workflow_state', {
      workflow_state: 'true',
      value_key: 'wf-2',
    });

    vi.spyOn(window, 'confirm').mockReturnValue(true);
    fireEvent.click(rowOf('Intake').querySelector('button:last-child')!);
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
