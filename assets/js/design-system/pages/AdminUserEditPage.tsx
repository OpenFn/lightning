import {
  AdminUserEditPage as DesignSystemAdminUserEditPage,
  type AdminUserRow,
  type UserFormValues,
} from '@openfn/ui';

import { designSystemPage } from '../page';

/** What UserLive.Edit puts in `data-props`. */
export interface Props {
  /** The account being edited; null on /settings/users/new. */
  user: AdminUserRow | null;
}

/** The design system's admin user form, fed by UserLive.Edit. */
export const AdminUserEditPage = designSystemPage(
  'AdminUserEditPage',
  DesignSystemAdminUserEditPage,
  ['/settings/users/new', '/settings/users/:id'],
  (props: Props, { send }) => ({
    ...props,
    // The server creates or updates the route's account, flashes and returns
    // to the list; a changeset failure rejects with field errors.
    onSave: (values: UserFormValues) => send('save_user', { ...values }),
  })
);
