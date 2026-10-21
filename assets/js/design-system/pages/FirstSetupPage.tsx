import DesignSystemFirstSetupPage, {
  type FirstSetupValues,
} from '@openfn/ui/pages/auth/FirstSetupPage.tsx';

import { designSystemPage } from '../page';

/** FirstSetupLive.Superuser sends no props: the page is one empty form. */
type Props = Record<string, never>;

/** The design system's first setup page, fed by FirstSetupLive.Superuser. */
export const FirstSetupPage = designSystemPage(
  'FirstSetupPage',
  DesignSystemFirstSetupPage,
  ['/first_setup'],
  (_props: Props, { send }) => ({
    // On success the server signs the new superuser in through a redirect;
    // a changeset failure rejects with the field errors.
    onSave: (values: FirstSetupValues) => send('save', { ...values }),
  })
);
