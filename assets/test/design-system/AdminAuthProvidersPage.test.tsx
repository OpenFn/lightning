import { fireEvent, screen, waitFor } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import {
  AdminAuthProvidersPage,
  type Props,
} from '../../js/design-system/pages/AdminAuthProvidersPage';

import { renderIsland } from './renderIsland';

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
    const { pushEvent } = renderIsland<Props>(AdminAuthProvidersPage, {
      provider,
    });
    pushEvent.mockResolvedValueOnce({ error: 'error parsing .well-known' });

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
