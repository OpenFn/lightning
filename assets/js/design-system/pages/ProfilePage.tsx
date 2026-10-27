import {
  ProfilePage as DesignSystemProfilePage,
  type MfaSetupResult,
  type ProfilePageProps,
} from '@openfn/ui';

import { designSystemPage } from '../page';

/** What ProfileLive.Edit puts in `data-props`. */
export type Props = Pick<
  ProfilePageProps,
  'user' | 'mfa' | 'github' | 'experimentalFeatures' | 'deletion' | 'deleting'
>;

/** The design system's profile page, fed by ProfileLive.Edit. */
export const ProfilePage = designSystemPage(
  'ProfilePage',
  DesignSystemProfilePage,
  ['/profile', '/profile/:id/delete'],
  (props: Props, { send, request, navigate }) => ({
    ...props,
    onSaveBasicInfo: values => send('save_basic_info', { ...values }),
    onChangeEmail: values => send('change_email', { ...values }),
    onChangePassword: values => send('change_password', { ...values }),
    // The secret arrives once, in the reply, never in props.
    onStartMfaSetup: () => request<MfaSetupResult>('start_mfa_setup'),
    onConfirmMfa: code => send('confirm_mfa', { code }),
    onDisableMfa: () => send('disable_mfa'),
    onDisconnectGithub: () => send('disconnect_github'),
    onSetExperimentalFeatures: on => send('set_experimental_features', { on }),
    onDeleteAccount: email => send('delete_account', { email }),
    onCloseDelete: () => navigate('/profile'),
  })
);
