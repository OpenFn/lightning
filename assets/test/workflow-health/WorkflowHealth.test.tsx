import { render, screen } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { SocketContext } from '#/react/contexts/SocketProvider';
import { HealthContent } from '#/workflow-health/WorkflowHealth';

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

const both = {
  get_outcomes: { ok: outcomes },
  get_failure_signatures: { ok: failureSignatures },
};

/**
 * Fake channel whose `push`/`join` replies are driven by a status → payload
 * map, so a test can pick which leg of the request fires. `push` is keyed by
 * event, so one request can fail while the other succeeds — the panels degrade
 * independently and the tests have to be able to say so.
 */
function fakeSocket(replies: Record<string, unknown>) {
  // Chainable `receive`, so `.receive('ok', ..).receive('error', ..)` both see
  // their callback. Fires whichever status the test put in `replies`.
  const chain = (statuses: Record<string, unknown>) => {
    const receive = (status: string, callback: (r: never) => void) => {
      if (status in statuses) callback(statuses[status] as never);
      return { receive };
    };
    return { receive };
  };

  const joinStatus = 'join_error' in replies ? 'error' : 'ok';

  const channel = {
    join: () => chain({ [joinStatus]: replies['join_error'] ?? {} }),
    push: (event: string) =>
      chain((replies[event] as Record<string, unknown>) ?? replies),
    leave: vi.fn(),
  };

  return { channel: () => channel, leaveSpy: channel.leave };
}

function mount(
  replies: Record<string, unknown>,
  connectionError: string | null = null
) {
  const socket = fakeSocket(replies);

  const rendered = render(
    <SocketContext.Provider
      value={{
        socket: socket as never,
        isConnected: true,
        connectionError,
        connect: vi.fn(),
        disconnect: vi.fn(),
      }}
    >
      <HealthContent
        workflowId="wf-1"
        projectId="proj-1"
        workflowName="Sync patients"
      />
    </SocketContext.Provider>
  );

  return { ...rendered, socket };
}

describe('WorkflowHealth', () => {
  test('renders the header, deriving the day count from the window', async () => {
    mount(both);

    expect(
      await screen.findByRole('heading', { name: 'Sync patients' })
    ).toBeInTheDocument();
    expect(screen.getByText('Last 30 days · 1,287 runs')).toBeVisible();
  });

  test('folds the failure states into the Outcomes donut', async () => {
    mount(both);

    // 98 + 24 + 12 + 7 — one reply feeds both donuts, so the two panels can
    // only disagree if this fold drifts from the breakdown's own total.
    expect(await screen.findByText('Failed')).toBeVisible();
    expect(screen.getByText('141')).toBeVisible();
    expect(screen.getByText('Success')).toBeVisible();
  });

  test('breaks the same failures down by run state', async () => {
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

  test('reports a rejected join without echoing the server', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    mount({ join_error: { reason: 'unauthorized' } });

    // A rejected join takes every panel with it — nothing was ever requested.
    expect(
      await screen.findAllByText(
        'Could not load workflow stats. Refresh to try again.'
      )
    ).toHaveLength(3);
    expect(screen.queryByText('unauthorized')).toBeNull();
  });

  test('surfaces a get_outcomes error reason', async () => {
    mount({ get_outcomes: { error: { reason: 'something broke' } } });

    // Both donuts read the same reply, so both degrade.
    expect(await screen.findAllByText('something broke')).toHaveLength(2);
  });

  // The whole point of requesting each slice separately: one failing query
  // must not blank the panels that answered.
  test('keeps the donuts when only the triage query fails', async () => {
    mount({
      get_outcomes: { ok: outcomes },
      get_failure_signatures: { error: { reason: 'triage query timed out' } },
    });

    expect(await screen.findByText('triage query timed out')).toBeVisible();
    expect(screen.getByText('Success')).toBeVisible();
    expect(screen.getByText('69.5%')).toBeVisible();
  });

  test('keeps the page around a failed chart', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    mount({ join_error: { reason: 'unauthorized' } });

    await screen.findAllByText(/Could not load workflow stats/);
    expect(
      screen.getByRole('heading', { name: 'Sync patients' })
    ).toBeVisible();
    expect(screen.getByRole('heading', { name: 'Outcomes' })).toBeVisible();
    expect(
      screen.getByRole('heading', { name: 'Failure breakdown' })
    ).toBeVisible();
    expect(screen.getByRole('heading', { name: 'Triage' })).toBeVisible();
  });

  test('reports a socket that never connects, rather than loading forever', async () => {
    mount({}, 'websocket closed');

    expect(
      await screen.findAllByText('Could not connect. Refresh to try again.')
    ).toHaveLength(3);
  });

  test('leaves the channel on unmount', () => {
    const { unmount, socket } = mount(both);

    unmount();

    expect(socket.leaveSpy).toHaveBeenCalled();
  });
});
