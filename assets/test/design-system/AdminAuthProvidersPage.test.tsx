import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { AdminAuthProvidersPage } from '../../js/design-system/pages/AdminAuthProvidersPage';

const provider = {
  id: 'ap1',
  name: 'google',
  discoveryUrl: 'https://accounts.google.com/.well-known/openid-configuration',
  clientId: 'client-id',
  hasClientSecret: true,
  redirectHost: 'http://localhost:4000',
  allowUnverifiedEmail: false,
};

const values = {
  name: 'google',
  discoveryUrl: 'https://accounts.google.com/.well-known/openid-configuration',
  clientId: 'client-id',
  clientSecret: '',
  redirectHost: 'http://localhost:4000',
  allowUnverifiedEmail: false,
};

describe('AdminAuthProvidersPage', () => {
  test('tests, saves and removes with the events the LiveView reads', async () => {
    const pushEvent = vi
      .fn()
      .mockResolvedValueOnce({ error: 'error parsing .well-known' })
      .mockResolvedValue({});
    render(
      <AdminAuthProvidersPage
        data-props={JSON.stringify({ provider })}
        pushEvent={pushEvent}
        handleEvent={vi.fn()}
        navigate={vi.fn()}
        redirect={vi.fn()}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: 'Test' }));
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('test_provider', values)
    );
    expect(await screen.findByText('error parsing .well-known')).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Failed' })).toBeTruthy();

    fireEvent.submit(document.getElementById('auth-provider-form')!);
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('save_provider', values)
    );

    fireEvent.click(screen.getByRole('button', { name: 'Remove' }));
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('remove_provider', {})
    );
  });
});
