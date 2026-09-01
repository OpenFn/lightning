import { render, screen } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { SocketContext } from '#/react/contexts/SocketProvider';
import { HealthContent } from '#/workflow-health/WorkflowHealth';

const outcomes = {
  window: { from: '2026-08-01T10:00:00Z', to: '2026-08-31T10:00:00Z' },
  counts: { success: 1211, failed: 61, pending: 12 },
};

/**
 * Fake channel whose `push`/`join` replies are driven by a status → payload
 * map, so a test can pick which leg of the request fires.
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
    push: () => chain(replies),
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
    mount({ ok: outcomes });

    expect(
      await screen.findByRole('heading', { name: 'Sync patients' })
    ).toBeInTheDocument();
    expect(screen.getByText('Last 30 days · 1,272 work orders')).toBeVisible();
  });

  test('reports a rejected join without echoing the server', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    mount({ join_error: { reason: 'unauthorized' } });

    expect(
      await screen.findByText(
        'Could not load workflow stats. Refresh to try again.'
      )
    ).toBeVisible();
    expect(screen.queryByText('unauthorized')).toBeNull();
  });

  test('surfaces a get_outcomes error reason', async () => {
    mount({ error: { reason: 'something broke' } });

    expect(await screen.findByText('something broke')).toBeVisible();
  });

  test('keeps the page around a failed chart', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    mount({ join_error: { reason: 'unauthorized' } });

    await screen.findByText(/Could not load workflow stats/);
    expect(
      screen.getByRole('heading', { name: 'Sync patients' })
    ).toBeVisible();
    expect(screen.getByRole('heading', { name: 'Outcomes' })).toBeVisible();
  });

  test('reports a socket that never connects, rather than loading forever', async () => {
    mount({}, 'websocket closed');

    expect(
      await screen.findByText('Could not connect. Refresh to try again.')
    ).toBeVisible();
  });

  test('leaves the channel on unmount', () => {
    const { unmount, socket } = mount({ ok: outcomes });

    unmount();

    expect(socket.leaveSpy).toHaveBeenCalled();
  });
});
