import DesignSystemAuthConfirmAccessPage, {
  type ConfirmAccessValues,
} from '@openfn/ui/pages/auth/AuthConfirmAccessPage.tsx';

import { designSystemPage } from '../page';

/** What ReAuthenticateLive.New puts in `data-props`. */
export interface Props {
  user: { firstName: string; lastName: string; mfaEnabled: boolean };
}

/** The design system's confirm access page, fed by ReAuthenticateLive.New. */
export const AuthConfirmAccessPage = designSystemPage(
  'AuthConfirmAccessPage',
  DesignSystemAuthConfirmAccessPage,
  ['/auth/confirm_access'],
  (props: Props, { send }) => ({
    ...props,
    // The same event and shape the HEEx form submitted. On success the
    // server sends the user on with the sudo token; a refusal rejects.
    onConfirm: (values: ConfirmAccessValues) =>
      send('reauthenticate-user', { user: values }),
  })
);
