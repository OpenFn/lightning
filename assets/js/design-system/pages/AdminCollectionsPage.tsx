import {
  type AdminCollectionRow,
  AdminCollectionsPage as DesignSystemAdminCollectionsPage,
  type CollectionFormValues,
} from '@openfn/ui';

import { designSystemPage } from '../page';

/** What CollectionLive.Index puts in `data-props`. */
export interface Props {
  collections: AdminCollectionRow[];
  projectOptions: [label: string, value: string][];
}

/** The design system's collections admin page, fed by CollectionLive.Index. */
export const AdminCollectionsPage = designSystemPage(
  'AdminCollectionsPage',
  DesignSystemAdminCollectionsPage,
  ['/settings/collections'],
  (props: Props, { send }) => ({
    ...props,
    // The server derives the URL-safe name, checks the project, flashes and
    // sends the list again; a changeset failure rejects with field errors.
    onCreate: (values: CollectionFormValues) =>
      send('create_collection', { ...values }),
    onUpdate: (id: string, values: CollectionFormValues) =>
      send('update_collection', { id, ...values }),
    onDelete: (id: string) => send('delete_collection', { collection: id }),
  })
);
