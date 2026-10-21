import {
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { ChannelsIndexPage } from '../../js/design-system/pages/ChannelsIndexPage';

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

const props = {
  project: { id: 'p1', parentId: null, color: null },
  projectLabel: 'Malawi HIV',
  channels: [channel],
  totalChannels: 1,
  totalRequests: 2,
  logsHref: '/projects/p1/history/channels',
  canCreateChannel: true,
  canEditChannel: true,
  canDeleteChannel: true,
  form: null as unknown,
};

const form = {
  channel: undefined,
  credentialOptions: [{ id: 'pc1', name: 'My API Key' }],
  authMethodOptions: [{ id: 'wam1', name: 'API Key Auth' }],
};

const renderPage = (
  overrides: Partial<typeof props> = {},
  reply: Record<string, unknown> = {}
) => {
  const pushEvent = vi.fn().mockResolvedValue(reply);
  const navigate = vi.fn();
  render(
    <ChannelsIndexPage
      data-props={JSON.stringify({ ...props, ...overrides })}
      pushEvent={pushEvent}
      handleEvent={vi.fn()}
      navigate={navigate}
      redirect={vi.fn()}
    />
  );
  return { pushEvent, navigate };
};

describe('ChannelsIndexPage', () => {
  test('switches and deletes with the payloads the LiveView reads', () => {
    const { pushEvent } = renderPage();
    const row = screen.getByText('lab-results').closest('tr')!;
    fireEvent.click(within(row).getByRole('switch'));
    expect(pushEvent).toHaveBeenCalledWith('toggle_channel_state', {
      channel_state: 'false',
      value_key: 'c1',
    });

    vi.spyOn(window, 'confirm').mockReturnValue(true);
    fireEvent.click(within(row).getByRole('button', { name: 'Delete' }));
    expect(pushEvent).toHaveBeenCalledWith('delete_channel', { id: 'c1' });
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
    await waitFor(() =>
      expect(navigate).toHaveBeenCalledWith('/projects/p1/channels', undefined)
    );
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
