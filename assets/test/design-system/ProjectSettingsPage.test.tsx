import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, test } from 'vitest';

import {
  ProjectSettingsPage,
  type Props,
} from '../../js/design-system/pages/ProjectSettingsPage';

import { renderIsland } from './renderIsland';

const props: Props = {
  project: { id: 'p1', parentId: null, color: null },
  projectLabel: 'my-project',
  parent: null,
  deleting: false,
  setup: {
    name: 'my-project',
    description: '',
    env: '',
    concurrency: null,
    exportHref: '/download/yaml?id=p1',
    deleteHref: '/projects/p1/settings/delete',
    gracePeriodDays: 7,
    scheduledDeletion: null,
    sandboxDeletion: null,
    canEditProject: true,
    canDeleteProject: true,
  },
  credentials: {
    credentials: [],
    oauthClients: [],
    projects: [],
    credentialTypes: [],
    oauthSignIns: [],
    canCreateGlobalOauthClient: false,
    keychainCredentials: [],
    canCreateProjectCredential: true,
    canCreateKeychainCredential: true,
    canEditKeychainCredential: true,
  },
  collections: { collections: [], canManage: true },
  webhookSecurity: { authMethods: [], canWrite: true },
  collaboration: {
    collaborators: [],
    supportAccess: false,
    canEditProject: true,
    canAddProjectUser: true,
    addBlockedReason: null,
    canReceiveFailureAlerts: true,
  },
  security: { requiresMfa: false, canEditProject: true, canRequireMfa: true },
  githubSync: {
    enabled: false,
    connection: null,
    userConnected: false,
    connectAccountHref: '',
    canInstall: true,
    canInitiateSync: true,
  },
  dataStorage: {
    historyRetentionPeriod: null,
    dataclipRetentionPeriod: null,
    retentionPolicy: 'retain_all',
    periods: [7, 14],
    limitMessage: null,
    canEdit: true,
  },
  historyExports: [],
};

// The Save button of the form with this id.
const save = (form: string) =>
  within(document.getElementById(form)!).getByRole('button', { name: 'Save' });

describe('ProjectSettingsPage', () => {
  afterEach(() => {
    window.history.replaceState(null, '', '/');
  });

  test('saves Project Identity with the name as typed', async () => {
    window.history.replaceState(null, '', '/projects/p1/settings#project');
    const { pushEvent } = renderIsland<Props>(ProjectSettingsPage, props);

    const name = screen.getByLabelText('Project name');
    await userEvent.clear(name);
    await userEvent.type(name, 'My Project');
    await userEvent.click(save('project-settings-form'));

    expect(pushEvent).toHaveBeenCalledWith('save_identity', {
      rawName: 'My Project',
      description: '',
    });
  });

  test("puts the server's field error under the name", async () => {
    window.history.replaceState(null, '', '/projects/p1/settings#project');
    renderIsland<Props>(ProjectSettingsPage, props, {
      reply: {
        error: 'Please fix the errors below.',
        fieldErrors: { rawName: ["can't be blank"] },
      },
    });

    await userEvent.click(save('project-settings-form'));

    expect(await screen.findByText("can't be blank")).toBeInTheDocument();
  });

  test('saves Concurrency Override as 1 for one run at a time', async () => {
    window.history.replaceState(null, '', '/projects/p1/settings#project');
    const { pushEvent } = renderIsland<Props>(ProjectSettingsPage, props);

    await userEvent.click(
      screen.getByRole('switch', { name: /Disable parallel execution/ })
    );
    await userEvent.click(save('project-concurrency-form'));

    expect(pushEvent).toHaveBeenCalledWith('save_concurrency', {
      concurrency: 1,
    });
  });

  test('saves no Concurrency Override when parallel runs are turned back on', async () => {
    window.history.replaceState(null, '', '/projects/p1/settings#project');
    const { pushEvent } = renderIsland<Props>(ProjectSettingsPage, {
      ...props,
      setup: { ...props.setup, concurrency: 1 },
    });

    await userEvent.click(
      screen.getByRole('switch', { name: /Disable parallel execution/ })
    );
    await userEvent.click(save('project-concurrency-form'));

    expect(pushEvent).toHaveBeenCalledWith('save_concurrency', {
      concurrency: null,
    });
  });

  test('sends the typed name to delete, and Cancel goes back', async () => {
    window.history.replaceState(null, '', '/projects/p1/settings/delete');
    const { pushEvent, navigate } = renderIsland<Props>(ProjectSettingsPage, {
      ...props,
      deleting: true,
    });

    await userEvent.type(
      screen.getByRole('textbox', { name: /name/i }),
      'my-project'
    );
    await userEvent.click(screen.getByRole('button', { name: /^Delete/ }));

    expect(pushEvent).toHaveBeenCalledWith('delete_project', {
      nameConfirmation: 'my-project',
    });

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(navigate).toHaveBeenCalledWith('/projects/p1/settings', undefined);
  });

  test('creates a keychain from the Add new menu', async () => {
    window.history.replaceState(null, '', '/projects/p1/settings#credentials');
    const { pushEvent } = renderIsland<Props>(ProjectSettingsPage, props);

    await userEvent.click(screen.getByRole('button', { name: /Add new/ }));
    await userEvent.click(screen.getByRole('menuitem', { name: 'Keychain' }));
    const form = screen.getByRole('dialog');
    await userEvent.type(within(form).getByLabelText(/^Name/), 'By facility');
    await userEvent.type(
      within(form).getByLabelText(/JSONPath Expression/),
      '$.facility'
    );
    await userEvent.click(within(form).getByRole('button', { name: 'Create' }));

    expect(pushEvent).toHaveBeenCalledWith(
      'create_keychain_credential',
      expect.objectContaining({ name: 'By facility', path: '$.facility' })
    );
  });

  test('creates a collection from the name as typed', async () => {
    window.history.replaceState(null, '', '/projects/p1/settings#collections');
    const { pushEvent } = renderIsland<Props>(ProjectSettingsPage, props);

    await userEvent.click(
      screen.getByRole('button', { name: 'Create collection' })
    );
    await userEvent.type(
      within(screen.getByRole('dialog')).getByLabelText(/Name/),
      'My Things'
    );
    await userEvent.click(
      within(screen.getByRole('dialog')).getByRole('button', { name: 'Save' })
    );

    expect(pushEvent).toHaveBeenCalledWith('create_collection', {
      rawName: 'My Things',
    });
  });

  test("previews a collection's first record from the reply", async () => {
    window.history.replaceState(null, '', '/projects/p1/settings#collections');
    const { pushEvent } = renderIsland<Props>(
      ProjectSettingsPage,
      {
        ...props,
        collections: {
          canManage: true,
          collections: [
            {
              id: 'c1',
              name: 'things',
              byteSizeSum: 0,
              downloadHref: '/download/collections/p1/things',
            },
          ],
        },
      },
      { reply: { record: '[{"key": "k1"}]' } }
    );

    await userEvent.click(
      screen.getByRole('button', { name: 'Preview collection' })
    );

    expect(pushEvent).toHaveBeenCalledWith('preview_collection', { id: 'c1' });
    expect(await screen.findByText('[{"key": "k1"}]')).toBeInTheDocument();
  });

  test("adds collaborators, then puts an invite's email error on its row", async () => {
    window.history.replaceState(
      null,
      '',
      '/projects/p1/settings#collaboration'
    );
    const { pushEvent } = renderIsland<Props>(ProjectSettingsPage, props);
    pushEvent
      .mockResolvedValueOnce({
        toInvite: [{ email: 'new@example.org', role: 'editor' }],
      })
      .mockResolvedValueOnce({
        error: 'Please fix the errors below.',
        fieldErrors: {
          'invitedCollaborators.0.email': ['This email is already taken'],
        },
      });

    await userEvent.click(
      screen.getByRole('button', { name: /Add Collaborator/ })
    );
    const add = within(screen.getByRole('dialog'));
    await userEvent.type(add.getByLabelText('Email'), 'new@example.org');
    await userEvent.selectOptions(add.getByLabelText('Role'), 'editor');
    await userEvent.click(
      add.getByRole('button', { name: /Save Collaborator/ })
    );

    expect(pushEvent).toHaveBeenCalledWith('add_collaborators', {
      collaborators: [{ email: 'new@example.org', role: 'editor' }],
    });

    const invite = within(
      await screen.findByRole('dialog', { name: /Invite new user/ })
    );
    await userEvent.type(invite.getByLabelText('First Name'), 'Ada');
    await userEvent.type(invite.getByLabelText('Last Name'), 'Lovelace');
    await userEvent.click(
      invite.getByRole('button', { name: /Invite new user/ })
    );

    expect(pushEvent).toHaveBeenLastCalledWith('invite_collaborators', {
      collaborators: [
        {
          email: 'new@example.org',
          role: 'editor',
          firstName: 'Ada',
          lastName: 'Lovelace',
        },
      ],
    });
    expect(
      await invite.findByText('This email is already taken')
    ).toBeInTheDocument();
  });

  test('sets MFA to the value chosen', async () => {
    window.history.replaceState(null, '', '/projects/p1/settings#security');
    const { pushEvent } = renderIsland<Props>(ProjectSettingsPage, props);

    await userEvent.click(screen.getByRole('switch', { name: /Require MFA/ }));

    expect(pushEvent).toHaveBeenCalledWith('set_requires_mfa', { on: true });
  });

  test('saves the retention periods as numbers', async () => {
    window.history.replaceState(null, '', '/projects/p1/settings#data-storage');
    const { pushEvent } = renderIsland<Props>(ProjectSettingsPage, props);

    await userEvent.selectOptions(
      screen.getByLabelText('History Retention Period'),
      '14'
    );
    await userEvent.click(save('retention-settings-form'));

    expect(pushEvent).toHaveBeenCalledWith('save_data_storage', {
      historyRetentionPeriod: 14,
      dataclipRetentionPeriod: null,
      retentionPolicy: 'retain_all',
    });
  });
});
