import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test } from 'vitest';

import {
  ProjectsDashboardPage,
  type Props,
} from '../../js/design-system/pages/ProjectsDashboardPage';

import { renderIsland } from './renderIsland';

const project: Props['projects'][number] = {
  id: 'p1',
  name: 'Malawi HIV',
  role: 'owner',
  workflowsCount: 2,
  collaboratorsCount: 3,
  lastUpdatedAt: '2026-10-01T10:00:00Z',
};

const renderPage = (reply: Record<string, unknown> = {}) =>
  renderIsland<Props>(
    ProjectsDashboardPage,
    { firstName: 'Amy', projects: [project] },
    { reply }
  );

const createProject = async (name: string) => {
  await userEvent.click(screen.getByRole('button', { name: 'Create project' }));
  await userEvent.type(screen.getByLabelText(/Name/), name);
  await userEvent.click(
    screen.getByRole('dialog').querySelector('button[type=submit]')!
  );
};

describe('ProjectsDashboardPage', () => {
  test('creating a project sends the url-safe name', async () => {
    const { pushEvent } = renderPage();
    expect(screen.getByText('Malawi HIV')).toBeInTheDocument();

    await createProject('My Awesome Project');

    expect(pushEvent).toHaveBeenCalledWith('create_project', {
      rawName: 'my-awesome-project',
      description: '',
    });
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull());
  });

  test('a refused create shows the field error on the name', async () => {
    renderPage({
      error: 'Please fix the errors below.',
      fieldErrors: { rawName: ['has already been taken'] },
    });

    await createProject('Taken');

    expect(
      await screen.findByText('has already been taken')
    ).toBeInTheDocument();
    expect(screen.getByRole('dialog')).toBeInTheDocument();
  });
});
