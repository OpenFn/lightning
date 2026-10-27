import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import {
  credentialActions,
  CredentialsIndexPage,
  type Props,
} from '../../js/design-system/pages/CredentialsIndexPage';

import { renderIsland } from './renderIsland';

const credential: Props['credentials'][number] = {
  id: 'c1',
  name: 'DHIS2 prod',
  schema: 'dhis2',
  oauthClient: null,
  ownerEmail: 'me@example.com',
  projects: [],
  externalId: null,
  environments: ['main'],
  transferStatus: null,
  scheduledDeletion: null,
  hasActivityInProjects: false,
  canEdit: true,
};

const props: Props = {
  credentials: [credential],
  oauthClients: [],
  projects: [{ id: 'p1', name: 'Malawi HIV' }],
  credentialTypes: [{ key: 'dhis2', name: 'dhis2' }],
  oauthSignIns: [],
  canCreateGlobalOauthClient: false,
};

describe('CredentialsIndexPage', () => {
  test('asks the LiveView to schedule a deletion, naming the credential as id', async () => {
    const { pushEvent } = renderIsland<Props>(CredentialsIndexPage, props);
    const row = screen.getByRole('row', { name: /DHIS2 prod/ });
    fireEvent.click(within(row).getByRole('button', { name: 'Actions' }));
    fireEvent.click(await screen.findByRole('menuitem', { name: 'Delete' }));
    fireEvent.click(
      await screen.findByRole('button', { name: 'Delete credential' })
    );

    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('delete_credential', {
        id: 'c1',
        now: false,
      })
    );
  });

  test('loads the stored values with a request before the edit form opens', async () => {
    const { pushEvent } = renderIsland<Props>(CredentialsIndexPage, props, {
      reply: {
        environments: [{ name: 'main', body: '{}', oauth: null }],
        fields: [],
      },
    });
    const row = screen.getByRole('row', { name: /DHIS2 prod/ });
    fireEvent.click(within(row).getByRole('button', { name: 'Actions' }));
    fireEvent.click(await screen.findByRole('menuitem', { name: 'Edit' }));

    await waitFor(() => {
      expect(pushEvent).toHaveBeenCalledWith('load_credential_secrets', {
        id: 'c1',
      });
      expect(pushEvent).toHaveBeenCalledWith('load_credential_schema', {
        key: 'dhis2',
      });
    });
  });

  test('sends each action as its event, with the record as id', () => {
    const send = vi.fn().mockResolvedValue(undefined);
    const request = vi.fn().mockResolvedValue({});
    const actions = credentialActions({
      send,
      request,
      subscribe: vi.fn(),
      navigate: vi.fn(),
    });
    const values = { name: 'n' } as never;

    void actions.onCreateCredential(values);
    void actions.onUpdateCredential('c1', values);
    void actions.onCancelCredentialDeletion('c1');
    void actions.onTransferCredential('c1', 'you@example.com');
    void actions.onRevokeCredentialTransfer('c1');
    void actions.onDiscardOauthSignIns('form-1');
    void actions.onCreateOauthClient(values);
    void actions.onUpdateOauthClient('o1', values);
    void actions.onDeleteOauthClient('o1');
    void actions.onAuthorizeOauth(values);
    void actions.onLoadOauthClientSecrets('o1');

    expect(send.mock.calls).toEqual([
      ['create_credential', { name: 'n' }],
      ['update_credential', { name: 'n', id: 'c1' }],
      ['cancel_credential_deletion', { id: 'c1' }],
      ['transfer_credential', { id: 'c1', receiverEmail: 'you@example.com' }],
      ['revoke_credential_transfer', { id: 'c1' }],
      ['discard_oauth_sign_ins', { formId: 'form-1' }],
      ['create_oauth_client', { name: 'n' }],
      ['update_oauth_client', { name: 'n', id: 'o1' }],
      ['delete_oauth_client', { id: 'o1' }],
    ]);
    expect(request.mock.calls).toEqual([
      ['authorize_oauth', { name: 'n' }],
      ['load_oauth_client_secrets', { id: 'o1' }],
    ]);
  });
});
