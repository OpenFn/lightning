import { screen } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import {
  ChannelRequestShowPage,
  type Props,
} from '../../js/design-system/pages/ChannelRequestShowPage';

import { renderIsland } from './renderIsland';

const props: Props = {
  project: { id: 'p1', parentId: null, color: null },
  projectLabel: 'Malawi HIV',
  request: {
    id: '4f1c9a8e-2b6d-4e1f-9c3a-7d5e8b2a1f60',
    state: 'success',
    startedAt: '2026-04-10T10:00:00.000000Z',
    completedAt: '2026-04-10T10:00:00.350000Z',
    clientIdentity: '192.168.1.1',
    clientAuth: 'API key',
    destinationAuth: 'None',
    isWiped: false,
    snapshot: {
      name: 'orders',
      destinationUrl: 'https://d.example.com',
      lockVersion: 1,
    },
    events: [],
  },
  channel: {
    id: 'c1',
    projectId: 'p1',
    name: 'orders',
    destinationUrl: 'https://d.example.com',
    lockVersion: 1,
  },
  canEditDataRetention: true,
  adminContacts: [],
};

describe('ChannelRequestShowPage', () => {
  test('draws the page from data-props', () => {
    renderIsland<Props>(ChannelRequestShowPage, props);
    expect(screen.getByText(/Channel Request/).textContent).toContain(
      '4f1c9a8e'
    );
    expect(screen.getByText('192.168.1.1')).toBeTruthy();
    expect(
      screen.getByRole('link', { name: 'orders' }).getAttribute('href')
    ).toBe('/projects/p1/channels/c1/edit');
  });
});
