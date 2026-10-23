import {
  AdminAuditPage as DesignSystemAdminAuditPage,
  type AdminAuditPageProps,
} from '@openfn/ui';

import { designSystemPage } from '../page';

/** What AuditLive.Index puts in `data-props`: the page's props as they are. */
export type Props = AdminAuditPageProps;

/** The design system's audit trail, fed by AuditLive.Index. Its pages are URL patches. */
export const AdminAuditPage = designSystemPage(
  'AdminAuditPage',
  DesignSystemAdminAuditPage,
  ['/settings/audit'],
  (props: Props) => props
);
