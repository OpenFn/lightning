import {
  AuthConfirmationRequiredPage as DesignSystemAuthConfirmationRequiredPage,
  type ChangeEmailResult,
  type ChangeEmailValues,
  type ResendResult,
} from '@openfn/ui';

import { designSystemPage } from '../page';

/** What UserConfirmationRequiredLive puts in `data-props`. */
export interface Props {
  email: string;
}

/** The design system's confirmation-required page, fed by UserConfirmationRequiredLive. */
export const AuthConfirmationRequiredPage = designSystemPage(
  'AuthConfirmationRequiredPage',
  DesignSystemAuthConfirmationRequiredPage,
  ['/users/confirm-required'],
  (props: Props, { request }) => ({
    ...props,
    // Both answers are statuses the page shows, so they come back as the
    // reply; a bad address or password rejects with field errors.
    onResend: () => request<ResendResult>('resend_confirmation_email'),
    onChangeEmail: (values: ChangeEmailValues) =>
      request<ChangeEmailResult>('change_email', { ...values }),
    // A controller route: the kit's router makes it a full load.
    logoutTo: '/users/log_out',
  })
);
