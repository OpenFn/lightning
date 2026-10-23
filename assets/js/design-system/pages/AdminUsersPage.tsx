import DesignSystemAdminUsersPage from '@openfn/ui/pages/admin/AdminUsersPage.tsx';
import type { AdminDeleteUser, AdminUserRow } from '@openfn/ui/types/admin.ts';

import { designSystemPage } from '../page';

/** What UserLive.Index puts in `data-props`. */
export interface Props {
  users: AdminUserRow[];
  /** Set while the route has the deletion dialog open. */
  deleteUser: AdminDeleteUser | null;
}

/** The design system's users admin page, fed by UserLive.Index. */
export const AdminUsersPage = designSystemPage(
  'AdminUsersPage',
  DesignSystemAdminUsersPage,
  ['/settings/users', '/settings/users/:id/delete'],
  (props: Props, { send, navigate }) => ({
    ...props,
    onCancelDeletion: (id: string) => send('cancel_deletion', { id }),
    // The server acts on the account the route opened; the email confirms.
    onDelete: (email: string) => send('delete_user', { email }),
    // The list is in another live_session: LiveView answers this patch with
    // a redirect, the full load today's links make.
    onClose: () => navigate('/settings/users'),
  })
);
