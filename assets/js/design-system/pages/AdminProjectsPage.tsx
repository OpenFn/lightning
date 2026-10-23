import DesignSystemAdminProjectsPage from '@openfn/ui/pages/admin/AdminProjectsPage.tsx';
import type {
  AdminDeleteProject,
  AdminProjectForm,
  AdminProjectFormValues,
  AdminProjectRow,
} from '@openfn/ui/types/admin.ts';

import { designSystemPage } from '../page';

/** What ProjectLive.Index puts in `data-props`. */
export interface Props {
  projects: AdminProjectRow[];
  /** Set while the route has the form open. */
  form: AdminProjectForm | null;
  /** Set while the route has the deletion dialog open. */
  deleteProject: AdminDeleteProject | null;
  gracePeriodDays: number;
}

/** The design system's projects admin page, fed by ProjectLive.Index. */
export const AdminProjectsPage = designSystemPage(
  'AdminProjectsPage',
  DesignSystemAdminProjectsPage,
  [
    '/settings/projects',
    '/settings/projects/new',
    '/settings/projects/:id',
    '/settings/projects/:id/delete',
  ],
  (props: Props, { send, navigate }) => ({
    ...props,
    // The server knows whether the open form creates or edits, and which
    // project the dialog opened; it flashes and returns to the list.
    onSave: (values: AdminProjectFormValues) =>
      send('save_project', { ...values }),
    onDelete: (nameConfirmation: string) =>
      send('delete_project', { nameConfirmation }),
    onCancelDeletion: (id: string) => send('cancel_deletion', { id }),
    onClose: () => navigate('/settings/projects'),
  })
);
