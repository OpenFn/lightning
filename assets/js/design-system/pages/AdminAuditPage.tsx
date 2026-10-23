import {
  AdminAuditPage as DesignSystemAdminAuditPage,
  type AuditEvent,
} from '@openfn/ui';

import { designSystemPage } from '../page';

/** What AuditLive.Index puts in `data-props`. */
export interface Props {
  events: AuditEvent[];
  pageNumber: number;
  pageSize: number;
  totalEntries: number;
}

/** The design system's audit trail, fed by AuditLive.Index. */
export const AdminAuditPage = designSystemPage(
  'AdminAuditPage',
  DesignSystemAdminAuditPage,
  ['/settings/audit'],
  (props: Props, { navigate }) => ({
    ...props,
    onPage: (page: number) => navigate(`/settings/audit?page=${page}`),
  })
);
