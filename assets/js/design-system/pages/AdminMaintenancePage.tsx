import DesignSystemAdminMaintenancePage from '@openfn/ui/pages/admin/AdminMaintenancePage.tsx';

import { designSystemPage } from '../page';

/** MaintenanceLive.Index sends no props: the page is two actions. */
type Props = Record<string, never>;

/** The design system's maintenance page, fed by MaintenanceLive.Index. */
export const AdminMaintenancePage = designSystemPage(
  'AdminMaintenancePage',
  DesignSystemAdminMaintenancePage,
  ['/settings/maintenance'],
  (_props: Props, { send }) => ({
    // The server answers each with a flash: queued or started at once, and
    // the icon refresh's result when it finishes.
    onRefreshAdaptors: () => send('refresh_adaptors'),
    onRefreshIcons: () => send('refresh_icons'),
  })
);
