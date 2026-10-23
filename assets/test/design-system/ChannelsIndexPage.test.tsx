import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import {
  ChannelsIndexPage,
  type Props,
} from '../../js/design-system/pages/ChannelsIndexPage';

import { renderIsland } from './renderIsland';

const channel = {
  id: 'c1',
  name: 'lab-results',
  enabled: true,
  destinationUrl: 'https://destination.example.com/data',
  proxyUrl: 'https://lightning.example.com/channels/c1',
  requestCount: 2,
  lastActivityAt: '2025-03-05T14:30:00Z',
  logsHref: '/projects/p1/history/channels?filters[channel_id]=c1',
};

const props: Props = {
  project: { id: 'p1', parentId: null, color: null },
  projectLabel: 'Malawi HIV',
  channels: [channel],
  totalChannels: 1,
  totalRequests: 2,
  logsHref: '/projects/p1/history/channels',
  canCreateChannel: true,
  canEditChannel: true,
  canDeleteChannel: true,
  form: null,
};

const form: Props['form'] = {
  channel: null,
  credentialOptions: [{ id: 'pc1', name: 'My API Key' }],
  authMethodOptions: [{ id: 'wam1', name: 'API Key Auth' }],
};

const renderPage = (
  overrides: Partial<Props> = {},
  reply: Record<string, unknown> = {}
) =>
  renderIsland<Props>(ChannelsIndexPage, { ...props, ...overrides }, { reply });

describe('ChannelsIndexPage', () => {
  test('switches and deletes with the payloads the LiveView reads', async () => {
    const { pushEvent } = renderPage();
    const row = screen.getByText('lab-results').closest('tr')!;
    fireEvent.click(within(row).getByRole('switch'));
    expect(pushEvent).toHaveBeenCalledWith('toggle_channel_state', {
      channel_state: 'false',
      value_key: 'c1',
    });

    fireEvent.click(within(row).getByRole('button', { name: 'Delete' }));
    fireEvent.click(
      within(screen.getByRole('dialog')).getByRole('button', { name: 'Delete' })
    );
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('delete_channel', { id: 'c1' })
    );
  });

  test('the form routes are patches of this LiveView', () => {
    const { navigate } = renderPage();
    fireEvent.click(screen.getByRole('button', { name: 'New Channel' }));
    expect(navigate).toHaveBeenCalledWith(
      '/projects/p1/channels/new',
      undefined
    );

    fireEvent.click(screen.getByRole('button', { name: 'Edit' }));
    expect(navigate).toHaveBeenCalledWith(
      '/projects/p1/channels/c1/edit',
      undefined
    );
  });

  test('saving sends every field and closes the form when the server agrees', async () => {
    const { pushEvent, navigate } = renderPage({ form });
    fireEvent.change(screen.getByLabelText('Name'), {
      target: { value: 'new-channel' },
    });
    fireEvent.change(screen.getByLabelText('Destination URL'), {
      target: { value: 'https://example.com/destination' },
    });
    fireEvent.click(screen.getByLabelText('API Key Auth'));
    fireEvent.submit(document.getElementById('channel-form-new')!);

    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('save_channel', {
        name: 'new-channel',
        enabled: true,
        destinationUrl: 'https://example.com/destination',
        destinationCredentialId: '',
        clientAuthMethodIds: ['wam1'],
      })
    );
    // The LiveView closes the form by patching back to the list.
    expect(navigate).not.toHaveBeenCalled();
  });

  test('a refused save shows the field error and keeps the form open', async () => {
    const { navigate } = renderPage(
      { form },
      {
        error: 'Please fix the errors below.',
        fieldErrors: {
          name: ['A channel with this name already exists in this project'],
        },
      }
    );
    fireEvent.change(screen.getByLabelText('Name'), {
      target: { value: 'existing' },
    });
    fireEvent.change(screen.getByLabelText('Destination URL'), {
      target: { value: 'https://example.com' },
    });
    fireEvent.submit(document.getElementById('channel-form-new')!);

    expect(
      await screen.findByText(
        'A channel with this name already exists in this project'
      )
    ).toBeInTheDocument();
    expect(navigate).not.toHaveBeenCalled();
  });
});
