import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test } from 'vitest';

import {
  HistoryWorkOrdersPage,
  type Props,
} from '../../js/design-system/pages/HistoryWorkOrdersPage';

import { renderIsland } from './renderIsland';

type Row = Props['rows'][number];

const row = (
  id: string,
  state: Row['state'],
  runState: Row['runs'][number]['state']
): Row => ({
  id,
  workflowId: 'w1',
  workflowName: 'Referrals',
  state,
  dataclipId: `dc-${id}`,
  dataclipWiped: false,
  insertedAt: '2026-10-14T09:29:00Z',
  lastActivity: '2026-10-14T09:30:05Z',
  runs: [
    {
      id: `run-${id}`,
      state: runState,
      insertedAt: '2026-10-14T09:30:00Z',
      claimedAt: null,
      startedAt: '2026-10-14T09:30:00Z',
      finishedAt: '2026-10-14T09:30:05Z',
      updatedAt: '2026-10-14T09:30:05Z',
      href: `/projects/p1/runs/run-${id}`,
      steps: [
        {
          id: `step-${id}`,
          jobId: 'j1',
          jobName: 'Intake',
          exitReason: state === 'pending' ? null : 'fail',
          errorType: null,
          startedAt: '2026-10-14T09:30:00Z',
          finishedAt: '2026-10-14T09:30:02Z',
          cloned: false,
          inputWiped: false,
          jobDeleted: false,
          href: `/projects/p1/runs/run-${id}?step=step-${id}`,
          inspectHref: `/projects/p1/w/w1?run=run-${id}&panel=editor&job=j1#log`,
        },
      ],
    },
  ],
  href: `/projects/p1/history?filters[workorder_id]=${id}`,
  workflowHref: `/projects/p1/w/w1?run=run-${id}`,
  dataclipHref: `/projects/p1/dataclips/dc-${id}/show`,
});

const props: Props = {
  project: { id: 'p1', parentId: null, color: null },
  projectLabel: 'Malawi HIV',
  channelsEnabled: false,
  workOrdersHref: '/projects/p1/history',
  channelLogsHref: '/projects/p1/history/channels',
  workflows: [
    { id: 'w1', name: 'Referrals', jobs: [{ id: 'j1', name: 'Intake' }] },
  ],
  filters: {
    workflowId: null,
    statuses: [],
    receivedAfter: null,
    receivedBefore: null,
    activityAfter: null,
    activityBefore: null,
    runStatuses: [],
    runCreatedAfter: null,
    runCreatedBefore: null,
    workorderId: null,
    errorSignature: null,
    searchTerm: '',
    searchFields: ['log'],
  },
  rows: [
    row('failed-wo', 'failed', 'failed'),
    row('pending-wo', 'pending', 'available'),
  ],
  state: 'ready',
  page: { number: 1, size: 10, totalEntries: 2 },
  sort: { key: 'last_activity', direction: 'desc' },
  searchLimit: 50,
  canRunWorkflow: true,
  dataStorageHref: null,
};

const rowOf = (id: string) =>
  document.getElementById(`toggle_details_for_${id}`)!;

describe('HistoryWorkOrdersPage', () => {
  test('sends each row action as the event the LiveView answers', async () => {
    const { pushEvent } = renderIsland<Props>(HistoryWorkOrdersPage, props);

    await userEvent.click(rowOf('failed-wo'));
    await userEvent.click(
      screen.getByRole('button', {
        name: 'Run this step with the latest version of this workflow',
      })
    );
    expect(pushEvent).toHaveBeenCalledWith('rerun', {
      run_id: 'run-failed-wo',
      step_id: 'step-failed-wo',
    });
    await userEvent.click(
      within(rowOf('failed-wo')).getByRole('button', {
        name: 'Retry (run from the start)',
      })
    );
    expect(pushEvent).toHaveBeenCalledWith('bulk-rerun', {
      type: 'selected',
      workorder_ids: ['failed-wo'],
    });

    await userEvent.click(
      within(rowOf('pending-wo')).getByRole('button', {
        name: 'Cancel pending run',
      })
    );
    expect(pushEvent).toHaveBeenCalledWith('cancel', {
      workorder_id: 'pending-wo',
    });

    await userEvent.click(rowOf('pending-wo'));
    await userEvent.click(
      screen.getByRole('button', { name: 'Cancel this run' })
    );
    expect(pushEvent).toHaveBeenCalledWith('cancel-run', {
      run_id: 'run-pending-wo',
    });
  });

  test('checks the run limit, then sends the bulk retry, the bulk cancel and the export', async () => {
    const { pushEvent } = renderIsland<Props>(HistoryWorkOrdersPage, props);

    await userEvent.click(document.getElementById('select_failed-wo')!);
    await userEvent.click(screen.getByRole('button', { name: 'Retry' }));
    expect(pushEvent).toHaveBeenCalledWith('validate_bulk_rerun', { count: 1 });
    await userEvent.click(
      await screen.findByRole('button', {
        name: 'Rerun 1 selected work order from start',
      })
    );
    expect(pushEvent).toHaveBeenCalledWith('bulk-rerun', {
      type: 'selected',
      workorder_ids: ['failed-wo'],
      job: null,
    });

    await userEvent.click(document.getElementById('select_failed-wo')!);
    await userEvent.click(screen.getByRole('button', { name: 'Retry from' }));
    await userEvent.click(
      await screen.findByRole('button', {
        name: 'Rerun 1 selected work order from selected job',
      })
    );
    expect(pushEvent).toHaveBeenCalledWith('bulk-rerun', {
      type: 'selected',
      workorder_ids: ['failed-wo'],
      job: 'j1',
    });

    await userEvent.click(document.getElementById('select_pending-wo')!);
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    await userEvent.click(
      await screen.findByRole('button', { name: 'Cancel up to 1 selected' })
    );
    expect(pushEvent).toHaveBeenCalledWith('bulk-cancel', {
      type: 'selected',
      workorder_ids: ['pending-wo'],
    });

    await userEvent.click(
      screen.getByRole('button', {
        name: 'Export all 2 results matching your query',
      })
    );
    await userEvent.click(
      await screen.findByRole('button', { name: 'Export history' })
    );
    expect(pushEvent).toHaveBeenCalledWith('confirm-export', {});
  });

  test('sends "all" for every matching work order when a whole page of many is ticked', async () => {
    const many = { number: 1, size: 2, totalEntries: 7 };
    const { pushEvent, unmount } = renderIsland<Props>(HistoryWorkOrdersPage, {
      ...props,
      rows: [row('a', 'failed', 'failed'), row('b', 'success', 'success')],
      page: many,
    });

    await userEvent.click(document.getElementById('select_all')!);
    await userEvent.click(screen.getByRole('button', { name: 'Retry' }));
    expect(pushEvent).toHaveBeenCalledWith('validate_bulk_rerun', { count: 2 });
    await userEvent.click(
      await screen.findByRole('button', {
        name: 'Rerun all 7 matching work orders from start',
      })
    );
    expect(pushEvent).toHaveBeenCalledWith('bulk-rerun', {
      type: 'all',
      job: null,
    });
    unmount();

    const pending = renderIsland<Props>(HistoryWorkOrdersPage, {
      ...props,
      rows: [
        row('c', 'pending', 'available'),
        row('d', 'pending', 'available'),
      ],
      page: many,
    });
    await userEvent.click(document.getElementById('select_all')!);
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    await userEvent.click(
      await screen.findByRole('button', { name: 'Cancel up to 7 matching' })
    );
    expect(pending.pushEvent).toHaveBeenCalledWith('bulk-cancel', {
      type: 'all',
    });
  });

  test('switches to the channel logs tab by patching the same LiveView', async () => {
    window.history.replaceState(null, '', '/projects/p1/history');
    const { navigate, redirect } = renderIsland<Props>(HistoryWorkOrdersPage, {
      ...props,
      channelsEnabled: true,
    });

    await userEvent.click(screen.getByRole('tab', { name: 'Channel Logs' }));

    expect(navigate).toHaveBeenCalledWith('/projects/p1/history/channels', {
      replace: false,
    });
    expect(redirect).not.toHaveBeenCalled();
  });
});
