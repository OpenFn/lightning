import {
  type AdminDeleteUser,
  type AdminUserRow,
  AdminUsersPage as DesignSystemAdminUsersPage,
} from '@openfn/ui';

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
    onClose: () => navigate('/settings/users'),
  })
);
