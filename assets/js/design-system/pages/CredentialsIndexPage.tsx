import {
  type CredentialActions,
  type CredentialSchemaResult,
  type CredentialSecretsResult,
  CredentialsIndexPage as DesignSystemCredentialsIndexPage,
  type CredentialsIndexPageProps,
  type OauthAuthorizeResult,
  type OauthClientSecretsResult,
} from '@openfn/ui';

import { designSystemPage, type PageActions } from '../page';

/** What CredentialLive.Index puts in `data-props`: the page's props minus its handlers. */
export type Props = Omit<CredentialsIndexPageProps, keyof CredentialActions>;

/**
 * The credential index's actions as LiveView events, each naming its record
 * as `id`. Project settings' Credentials tab sends the same events.
 */
export const credentialActions = ({
  send,
  request,
}: PageActions): CredentialActions => ({
  onCreateCredential: values => send('create_credential', { ...values }),
  onUpdateCredential: (id, values) =>
    send('update_credential', { ...values, id }),
  onLoadCredentialSecrets: id =>
    request<CredentialSecretsResult>('load_credential_secrets', { id }),
  onLoadCredentialSchema: key =>
    request<CredentialSchemaResult>('load_credential_schema', { key }),
  onDeleteCredential: (id, { now }) => send('delete_credential', { id, now }),
  onCancelCredentialDeletion: id => send('cancel_credential_deletion', { id }),
  onTransferCredential: (id, receiverEmail) =>
    send('transfer_credential', { id, receiverEmail }),
  onRevokeCredentialTransfer: id => send('revoke_credential_transfer', { id }),
  onAuthorizeOauth: values =>
    request<OauthAuthorizeResult>('authorize_oauth', { ...values }),
  onDiscardOauthSignIns: formId => send('discard_oauth_sign_ins', { formId }),
  onCreateOauthClient: values => send('create_oauth_client', { ...values }),
  onUpdateOauthClient: (id, values) =>
    send('update_oauth_client', { ...values, id }),
  onLoadOauthClientSecrets: id =>
    request<OauthClientSecretsResult>('load_oauth_client_secrets', { id }),
  onDeleteOauthClient: id => send('delete_oauth_client', { id }),
});

/**
 * The design system's Credentials page, fed by CredentialLive.Index. Its
 * modals are the page's own state, so it has one route.
 */
export const CredentialsIndexPage = designSystemPage(
  'CredentialsIndexPage',
  DesignSystemCredentialsIndexPage,
  ['/credentials'],
  (props: Props, actions) => ({ ...props, ...credentialActions(actions) })
);
