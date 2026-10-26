import {
  FirstSetupPage as DesignSystemFirstSetupPage,
  type FirstSetupValues,
  type FirstSetupPageProps,
} from '@openfn/ui';

import { designSystemPage } from '../page';

/** FirstSetupLive.Superuser sends no props: the page is one empty form. */
export type Props = Omit<FirstSetupPageProps, 'onSave'>;

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
