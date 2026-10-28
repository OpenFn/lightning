import {
  type AddCollaboratorsResult,
  ProjectSettingsPage as DesignSystemProjectSettingsPage,
  type ProjectSettingsPageProps,
  RequestError,
} from '@openfn/ui';

import { designSystemPage } from '../page';

import { credentialActions } from './CredentialsIndexPage';

/** What ProjectLive.Settings puts in `data-props`: the page's props minus its handlers. */
export type Props = Pick<
  ProjectSettingsPageProps,
  | 'project'
  | 'projectLabel'
  | 'parent'
  | 'deleting'
  | 'setup'
  | 'credentials'
  | 'collections'
  | 'webhookSecurity'
  | 'collaboration'
  | 'security'
  | 'githubSync'
  | 'dataStorage'
  | 'historyExports'
>;

/** Lightning keys an invite row's errors `invitedCollaborators.1.email`; the modal wants `1.email`. */
const rowErrors = (error: unknown): never => {
  if (!(error instanceof RequestError)) throw error;
  throw new RequestError(error.message, {
    fieldErrors: Object.fromEntries(
      Object.entries(error.fieldErrors).map(([key, messages]) => [
        key.replace(/^invitedCollaborators\./, ''),
        messages,
      ])
    ),
  });
};

/**
 * The design system's project settings page, fed by ProjectLive.Settings.
 * The tab is the URL hash, so the page has two routes: the settings and
 * the deletion modal over them. The Credentials tab sends the credential
 * index's events, as the user's Credentials page does.
 */
export const ProjectSettingsPage = designSystemPage(
  'ProjectSettingsPage',
  DesignSystemProjectSettingsPage,
  ['/projects/:project_id/settings', '/projects/:project_id/settings/delete'],
  (props: Props, actions) => {
    const { send, request, navigate } = actions;
    return {
      ...props,
      ...credentialActions(actions),
      onCreateKeychainCredential: values =>
        send('create_keychain_credential', { ...values }),
      onUpdateKeychainCredential: (id, values) =>
        send('update_keychain_credential', { ...values, id }),
      onDeleteKeychainCredential: id =>
        send('delete_keychain_credential', { id }),

      onSaveIdentity: values => send('save_identity', { ...values }),
      onSaveConcurrency: concurrency =>
        send('save_concurrency', { concurrency }),
      onDeleteProject: nameConfirmation =>
        send('delete_project', { nameConfirmation }),
      onCloseDelete: () => navigate(`/projects/${props.project.id}/settings`),

      onCreateCollection: rawName => send('create_collection', { rawName }),
      onRenameCollection: (id, rawName) =>
        send('rename_collection', { id, rawName }),
      onDeleteCollection: id => send('delete_collection', { id }),
      onPreviewCollection: id =>
        request<{ record: string | null }>('preview_collection', { id }).then(
          ({ record }) => record
        ),

      onCreateWebhookAuthMethod: values =>
        send('create_webhook_auth_method', { ...values }),
      onRenameWebhookAuthMethod: (id, name) =>
        send('rename_webhook_auth_method', { id, name }),
      onDeleteWebhookAuthMethod: id =>
        send('delete_webhook_auth_method', { id }),
      // Secrets arrive once, in the reply, never in props.
      onGenerateApiKey: () =>
        request<{ apiKey: string }>('generate_api_key').then(
          ({ apiKey }) => apiKey
        ),
      onRevealWebhookSecret: (id, values) =>
        request<{ secret: string }>('reveal_webhook_secret', {
          ...values,
          id,
        }).then(({ secret }) => secret),

      onAddCollaborators: collaborators =>
        request<AddCollaboratorsResult>('add_collaborators', { collaborators }),
      onInviteCollaborators: collaborators =>
        send('invite_collaborators', { collaborators }).catch(rowErrors),
      onRemoveCollaborator: id => send('remove_collaborator', { id }),
      onSetSupportAccess: on => send('set_support_access', { on }),
      onSetFailureAlert: (id, on) => send('set_failure_alert', { id, on }),
      onSetDigest: (id, digest) => send('set_digest', { id, digest }),

      onSetRequiresMfa: on => send('set_requires_mfa', { on }),
      onInitiateGithubSync: () => send('sync_github'),
      onRemoveGithubConnection: () => send('remove_github_connection'),
      onSaveDataStorage: values => send('save_data_storage', { ...values }),
    };
  }
);
