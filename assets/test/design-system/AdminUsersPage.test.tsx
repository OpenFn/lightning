import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test } from 'vitest';

import {
  AdminUsersPage,
  type Props,
} from '../../js/design-system/pages/AdminUsersPage';

import { renderIsland } from './renderIsland';

const props: Props = {
  users: [
    {
      id: 'u1',
      firstName: 'Amara',
      lastName: 'Okafor',
      email: 'amara@example.org',
      role: 'user',
      supportUser: false,
      disabled: true,
      scheduledDeletion: '2026-10-21T09:30:00Z',
    },
  ],
  deleteUser: {
    id: 'u1',
    email: 'amara@example.org',
    scheduledDeletion: '2026-10-21T09:30:00Z',
    hasActivityInProjects: false,
  },
};

const renderPage = (deleteUser = props.deleteUser) =>
  renderIsland<Props>(AdminUsersPage, { ...props, deleteUser });

describe('AdminUsersPage', () => {
  test('deletes with the event the LiveView reads', async () => {
    const { pushEvent } = renderPage();

    const dialog = screen.getByRole('dialog');
    fireEvent.change(within(dialog).getByLabelText('User email'), {
      target: { value: 'amara@example.org' },
    });
    fireEvent.click(
      within(dialog).getByRole('button', { name: 'Delete account' })
    );
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('delete_user', {
        email: 'amara@example.org',
      })
    );
  });

  test('cancels a deletion with the event the LiveView reads', async () => {
    const { pushEvent } = renderPage(null);

    await userEvent.click(screen.getByRole('button', { name: /Actions/ }));
    await userEvent.click(
      screen.getByRole('menuitem', { name: 'Cancel deletion' })
    );
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('cancel_deletion', { id: 'u1' })
    );
  });

  test('closing the dialog patches to the list', () => {
    const { navigate } = renderPage();
    fireEvent.click(
      within(screen.getByRole('dialog')).getByRole('button', { name: 'Cancel' })
    );
    expect(navigate).toHaveBeenCalledWith('/settings/users', undefined);
  });
});
