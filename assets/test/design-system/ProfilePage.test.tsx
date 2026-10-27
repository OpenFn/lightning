import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, test } from 'vitest';

import {
  ProfilePage,
  type Props,
} from '../../js/design-system/pages/ProfilePage';

import { renderIsland } from './renderIsland';

const props: Props = {
  user: {
    id: 'u1',
    firstName: 'Ada',
    lastName: 'Lovelace',
    email: 'ada@example.com',
    contactPreference: 'critical',
    insertedAt: '2026-01-01T00:00:00Z',
  },
  mfa: { enabled: false, backupCodesHref: '/profile/auth/backup_codes' },
  github: { connectHref: null, status: 'none' },
  experimentalFeatures: false,
  deletion: {
    href: '/profile/u1/delete',
    hasActivityInProjects: false,
    blocked: false,
  },
  deleting: false,
};

describe('ProfilePage', () => {
  afterEach(() => {
    window.history.replaceState(null, '', '/');
  });

  test('saves basic information with the form values', async () => {
    const { pushEvent } = renderIsland<Props>(ProfilePage, props);

    const firstName = screen.getByLabelText(/First name/);
    await userEvent.clear(firstName);
    await userEvent.type(firstName, 'Augusta');
    await userEvent.click(screen.getByRole('button', { name: 'Save' }));

    expect(pushEvent).toHaveBeenCalledWith('save_basic_info', {
      firstName: 'Augusta',
      lastName: 'Lovelace',
      contactPreference: 'critical',
    });
  });

  test('sends the email, password and preference changes with the keys the LiveView reads', async () => {
    const { pushEvent } = renderIsland<Props>(ProfilePage, props);

    await userEvent.type(
      screen.getByLabelText(/New email address/),
      'new@example.com'
    );
    await userEvent.type(
      screen.getByLabelText(/Enter password to confirm/),
      'secret-1'
    );
    await userEvent.click(screen.getByRole('button', { name: 'Update email' }));

    expect(pushEvent).toHaveBeenCalledWith('change_email', {
      email: 'new@example.com',
      currentPassword: 'secret-1',
    });

    await userEvent.type(
      screen.getByLabelText(/^New password/),
      'password1234'
    );
    await userEvent.type(
      screen.getByLabelText(/Confirm new password/),
      'password1234'
    );
    await userEvent.type(
      screen.getByLabelText(/^Current password/),
      'secret-1'
    );
    await userEvent.click(
      screen.getByRole('button', { name: 'Update password' })
    );

    expect(pushEvent).toHaveBeenCalledWith('change_password', {
      password: 'password1234',
      passwordConfirmation: 'password1234',
      currentPassword: 'secret-1',
    });

    await userEvent.click(
      screen.getByRole('switch', { name: /Experimental Features/ })
    );

    expect(pushEvent).toHaveBeenCalledWith('set_experimental_features', {
      on: true,
    });
  });

  test('the MFA secret comes from the reply, not from props', async () => {
    const { pushEvent } = renderIsland<Props>(ProfilePage, props, {
      reply: { secret: 'ABCDEF234567', qrCodeSrc: 'data:image/svg+xml,x' },
    });

    await userEvent.click(screen.getByRole('switch', { name: /multi-factor/ }));

    expect(pushEvent).toHaveBeenCalledWith('start_mfa_setup', {});
    expect(await screen.findByRole('img', { name: /QR code/ })).toHaveAttribute(
      'src',
      'data:image/svg+xml,x'
    );

    await userEvent.click(screen.getByText('this secret key'));
    expect(await screen.findByText('ABCDEF234567')).toBeInTheDocument();
  });

  test('closing the deletion modal goes back to the profile', async () => {
    window.history.replaceState(null, '', '/profile/u1/delete');
    const { navigate } = renderIsland<Props>(ProfilePage, {
      ...props,
      deleting: true,
    });

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(navigate).toHaveBeenCalledWith('/profile', undefined);
  });
});
