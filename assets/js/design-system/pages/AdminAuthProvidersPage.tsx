import {
  AdminAuthProvidersPage as DesignSystemAdminAuthProvidersPage,
  type AuthProviderValues,
  type AdminAuthProvidersPageProps,
} from '@openfn/ui';

import { designSystemPage } from '../page';

/** What AuthProvidersLive.Index puts in `data-props`. */
export type Props = Pick<AdminAuthProvidersPageProps, 'provider'>;

/** The design system's auth provider page, fed by AuthProvidersLive.Index. */
export const AdminAuthProvidersPage = designSystemPage(
  'AdminAuthProvidersPage',
  DesignSystemAdminAuthProvidersPage,
  ['/settings/authentication', '/settings/authentication/new'],
  (props: Props, { send }) => ({
    ...props,
    // The server knows whether it creates or updates, flashes, and after a
    // create shows the edit route; a refusal rejects with field errors.
    onSave: (values: AuthProviderValues) =>
      send('save_provider', { ...values }),
    // Resolves when the discovery document fetched; rejects with the reason.
    onTest: (values: AuthProviderValues) =>
      send('test_provider', { ...values }),
    onRemove: () => send('remove_provider'),
  })
);
