import { render, screen } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { HistoryChannelLogsPage } from '../../js/design-system/pages/HistoryChannelLogsPage';

const props = {
  project: { id: 'p1', parentId: null, color: null },
  projectLabel: 'Malawi HIV',
  channelsEnabled: true,
  channels: [{ id: 'c1', name: 'channel-one' }],
  channelId: 'c1',
  rows: [
    {
      id: 'r1',
      requestId: 'c81d3e5a-77f2-4c0b-a1e9-3b6f0d2c9e14',
      channelId: 'c1',
      channelName: 'channel-one',
      startedAt: '2026-10-14T09:31:12Z',
      state: 'success',
      requestPath: '/some/upstream/path',
      errorMessage: null,
    },
  ],
  page: { number: 1, size: 10, totalEntries: 1 },
};

describe('HistoryChannelLogsPage', () => {
  test('draws the page from data-props and patches for a new page', () => {
    const navigate = vi.fn();
    render(
      <HistoryChannelLogsPage
        data-props={JSON.stringify(props)}
        pushEvent={vi.fn()}
        handleEvent={vi.fn()}
        navigate={navigate}
        redirect={vi.fn()}
      />
    );
    expect(
      document.getElementById('channel-filter-chip')!.textContent
    ).toContain('Channel is channel-one');
    expect(
      screen.getByRole('link', { name: 'c81d3e5a' }).getAttribute('href')
    ).toBe('/projects/p1/history/channels/r1');
    expect(
      screen.getByRole('tab', { name: 'Work Orders' }).getAttribute('href')
    ).toBe('/projects/p1/history');
  });
});
