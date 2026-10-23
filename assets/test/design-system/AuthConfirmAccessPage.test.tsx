import { fireEvent, screen, waitFor } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import {
  AuthConfirmAccessPage,
  type Props,
} from '../../js/design-system/pages/AuthConfirmAccessPage';

import { renderIsland } from './renderIsland';

const renderPage = (reply: Record<string, unknown> = {}) =>
  renderIsland<Props>(
    AuthConfirmAccessPage,
    { user: { firstName: 'Amara', lastName: 'Diallo', mfaEnabled: true } },
    { reply }
  );

describe('AuthConfirmAccessPage', () => {
  test('confirms with the password or the code, as the HEEx form submitted', async () => {
    const { pushEvent } = renderPage();
    fireEvent.change(document.getElementById('user_password')!, {
      target: { value: 'secret' },
    });
    fireEvent.submit(document.getElementById('reauthentication-form')!);
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('reauthenticate-user', {
        user: { password: 'secret' },
      })
    );

    fireEvent.click(screen.getByText('Use your authenticator app instead'));
    fireEvent.change(document.getElementById('user_code')!, {
      target: { value: '123456' },
    });
    fireEvent.submit(document.getElementById('reauthentication-form')!);
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('reauthenticate-user', {
        user: { code: '123456' },
      })
    );
  });

  test('a refusal stays on the page with its message', async () => {
    renderPage({ error: 'Invalid password! Try again.' });
    fireEvent.change(document.getElementById('user_password')!, {
      target: { value: 'wrong' },
    });
    fireEvent.submit(document.getElementById('reauthentication-form')!);

    expect(
      await screen.findByText('Invalid password! Try again.')
    ).toBeInTheDocument();
  });
});
