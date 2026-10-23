import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test } from 'vitest';

import {
  AdminProjectsPage,
  type Props,
} from '../../js/design-system/pages/AdminProjectsPage';

import { renderIsland } from './renderIsland';

const row = {
  id: 'p1',
  name: 'malawi-hiv',
  description: 'HIV programme',
  insertedAt: '2026-01-02T03:04:00Z',
  ownerName: 'Amy Admin',
  scheduledDeletion: '2026-10-21T09:30:00Z',
};

const users = [
  { id: 'u1', firstName: 'Amy', lastName: 'Admin', email: 'amy@example.org' },
  { id: 'u2', firstName: 'Bob', lastName: 'Brown', email: 'bob@example.org' },
];

const renderPage = (props: Partial<Props>) =>
  renderIsland<Props>(AdminProjectsPage, {
    projects: [row],
    form: null,
    deleteProject: null,
    gracePeriodDays: 7,
    ...props,
  });

describe('AdminProjectsPage', () => {
  test('saves the open form with the name as typed and a role per user', async () => {
    const { pushEvent } = renderPage({
      form: {
        project: {
          id: 'p1',
          name: 'malawi-hiv',
          members: [{ userId: 'u1', role: 'owner' }],
        },
        users,
      },
    });
    fireEvent.click(document.getElementById('project_users_u2_role_editor')!);
    fireEvent.submit(document.getElementById('project-form')!);
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('save_project', {
        rawName: 'malawi-hiv',
        roles: { u1: 'owner', u2: 'editor' },
      })
    );
  });

  test('deletes with the typed name and cancels a deletion with the id', async () => {
    const { pushEvent } = renderPage({
      deleteProject: { id: 'p1', name: 'malawi-hiv' },
    });
    const dialog = screen.getByRole('dialog');
    fireEvent.change(within(dialog).getByLabelText('Project name'), {
      target: { value: 'malawi-hiv' },
    });
    fireEvent.click(
      within(dialog).getByRole('button', { name: 'Delete project' })
    );
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('delete_project', {
        nameConfirmation: 'malawi-hiv',
      })
    );
  });

  test('cancels a scheduled deletion from the row menu', async () => {
    const { pushEvent } = renderPage({});
    await userEvent.click(screen.getByRole('button', { name: /Actions/ }));
    await userEvent.click(
      screen.getByRole('menuitem', { name: 'Cancel deletion' })
    );
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('cancel_deletion', { id: 'p1' })
    );
  });

  test('closing the dialog patches to the list', () => {
    const { navigate } = renderPage({
      deleteProject: { id: 'p1', name: 'malawi-hiv' },
    });
    fireEvent.click(
      within(screen.getByRole('dialog')).getByRole('button', { name: 'Cancel' })
    );
    expect(navigate).toHaveBeenCalledWith('/settings/projects', undefined);
  });
});
