import DesignSystemAdminAuthProvidersPage from '@openfn/ui/pages/admin/AdminAuthProvidersPage.tsx';
import type {
  AuthProvider,
  AuthProviderValues,
} from '@openfn/ui/types/admin.ts';

import { designSystemPage } from '../page';

/** What AuthProvidersLive.Index puts in `data-props`. */
interface Props {
  /** The configured provider, or a blank one on /new. Never the secret. */
  provider: AuthProvider;
}

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
