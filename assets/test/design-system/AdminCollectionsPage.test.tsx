import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import {
  AdminCollectionsPage,
  type Props,
} from '../../js/design-system/pages/AdminCollectionsPage';

import { renderIsland } from './renderIsland';

const props: Props = {
  collections: [
    {
      id: 'c1',
      name: 'patients',
      projectId: 'p1',
      projectName: 'Malawi HIV',
      byteSizeSum: 2_500_000,
    },
  ],
  projectOptions: [
    ['Kenya TB', 'p2'],
    ['Malawi HIV', 'p1'],
  ],
};

describe('AdminCollectionsPage', () => {
  test('creates, updates and deletes with the events the LiveView reads', async () => {
    const { pushEvent } = renderIsland<Props>(AdminCollectionsPage, props);

    fireEvent.click(
      document.getElementById('open-create-collection-modal-button')!
    );
    fireEvent.change(screen.getByLabelText(/Name/), {
      target: { value: 'New Collection' },
    });
    fireEvent.change(screen.getByLabelText(/Project/), {
      target: { value: 'p2' },
    });
    fireEvent.submit(document.getElementById('collection-form-new')!);
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('create_collection', {
        rawName: 'New Collection',
        projectId: 'p2',
      })
    );
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull());

    fireEvent.click(document.getElementById('edit-collection-c1-button')!);
    fireEvent.change(screen.getByLabelText(/Name/), {
      target: { value: 'Patients 2' },
    });
    fireEvent.submit(document.getElementById('collection-form-c1')!);
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('update_collection', {
        id: 'c1',
        rawName: 'Patients 2',
        projectId: 'p1',
      })
    );
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull());

    fireEvent.click(document.getElementById('delete-collection-c1-button')!);
    fireEvent.click(
      within(screen.getByRole('dialog')).getByRole('button', { name: 'Delete' })
    );
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('delete_collection', {
        collection: 'c1',
      })
    );
  });
});
