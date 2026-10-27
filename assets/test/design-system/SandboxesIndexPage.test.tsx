import { fireEvent, screen, waitFor } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import {
  SandboxesIndexPage,
  type Props,
} from '../../js/design-system/pages/SandboxesIndexPage';

import { renderIsland } from './renderIsland';

const row = (id: string, name: string) => ({
  id,
  name,
  color: '#5AA1F0',
  env: null,
  scheduledDeletion: null,
  workflowsHref: `/projects/${id}/w`,
  editHref: `/projects/p1/sandboxes/${id}/edit`,
  canEdit: true,
  canDelete: true,
  canMerge: true,
  canCancelDeletion: false,
  restoreBlockedReason: null,
  activeDescendantCount: 0,
});

const props: Props = {
  project: { id: 'p1', parentId: null, color: null },
  projectLabel: 'openhie-project',
  root: { ...row('p1', 'openhie-project'), editHref: null },
  rootIsSandbox: false,
  sandboxes: [
    row('s1', 'fhir-mapping'),
    {
      ...row('s2', 'old-import'),
      scheduledDeletion: '2026-10-21T00:00:00Z',
      canEdit: false,
      canDelete: false,
      canMerge: false,
      canCancelDeletion: true,
    },
  ],
  newHref: '/projects/p1/sandboxes/new',
  createBlockedReason: null,
  gracePeriodDays: 7,
  form: null,
};

const newForm: Props['form'] = {
  mode: 'new',
  parentName: 'openhie-project',
  parentIsSandbox: false,
  initialColor: '#E33D63',
};

const preview = {
  targets: [{ id: 'p1', name: 'openhie-project' }],
  targetId: 'p1',
  workflows: [
    {
      id: 'w1',
      name: 'Changed one',
      isChanged: true,
      isDiverged: false,
      isNew: false,
      isDeleted: false,
    },
  ],
  credentials: [],
  collectionsToAdd: [],
};

const action = (kind: string, id: string) =>
  document.querySelector<HTMLButtonElement>(`#${kind}-sandbox-${id} button`)!;

const renderPage = (overrides: Partial<Props> = {}, reply: unknown = {}) =>
  renderIsland<Props>(
    SandboxesIndexPage,
    { ...props, ...overrides },
    { reply }
  );

describe('SandboxesIndexPage', () => {
  test('the create and edit routes are patches of this LiveView, and closing goes back to the list', () => {
    const { navigate } = renderPage({ form: newForm });
    fireEvent.click(document.getElementById('create-sandbox-button')!);
    expect(navigate).toHaveBeenCalledWith(
      '/projects/p1/sandboxes/new',
      undefined
    );

    fireEvent.click(action('edit', 's1'));
    expect(navigate).toHaveBeenCalledWith(
      '/projects/p1/sandboxes/s1/edit',
      undefined
    );

    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(navigate).toHaveBeenLastCalledWith(
      '/projects/p1/sandboxes',
      undefined
    );
  });

  test('creates and edits with the payloads the LiveView reads', async () => {
    const { pushEvent, setProps } = renderPage({ form: newForm });
    fireEvent.change(screen.getByLabelText(/Name/), {
      target: { value: 'My Test' },
    });
    fireEvent.submit(document.getElementById('sandbox-form')!);
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('create-sandbox', {
        rawName: 'My Test',
        color: '#E33D63',
      })
    );

    setProps({
      ...props,
      form: {
        mode: 'edit',
        sandboxId: 's1',
        initial: { rawName: 'fhir-mapping', color: '#5AA1F0' },
      },
    });
    fireEvent.submit(document.getElementById('sandbox-form')!);
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('update-sandbox', {
        id: 's1',
        rawName: 'fhir-mapping',
        color: '#5AA1F0',
      })
    );
  });

  test("shows the LiveView's name refusal on the field", async () => {
    renderPage(
      { form: newForm },
      {
        error: 'Please fix the errors below.',
        fieldErrors: { rawName: ['Sandbox name already exists'] },
      }
    );
    fireEvent.change(screen.getByLabelText(/Name/), {
      target: { value: 'fhir-mapping' },
    });
    fireEvent.submit(document.getElementById('sandbox-form')!);
    expect(
      await screen.findByText('Sandbox name already exists')
    ).toBeInTheDocument();
  });

  test('deletes with the typed name and restores by id', async () => {
    const { pushEvent } = renderPage();
    fireEvent.click(action('delete', 's1'));
    fireEvent.change(screen.getByLabelText(/Sandbox name/), {
      target: { value: 'fhir-mapping' },
    });
    fireEvent.submit(document.getElementById('confirm-delete-sandbox-form')!);
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('delete-sandbox', {
        id: 's1',
        nameConfirmation: 'fhir-mapping',
      })
    );

    fireEvent.click(action('cancel-deletion', 's2'));
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('cancel-sandbox-deletion', {
        id: 's2',
      })
    );
  });

  test('asks the LiveView for the preview, then merges what was ticked', async () => {
    const { pushEvent } = renderPage();
    pushEvent.mockResolvedValueOnce(preview);
    fireEvent.click(action('branch-rewire', 's1'));
    await screen.findByText('Workflows to merge');
    expect(pushEvent).toHaveBeenCalledWith('preview-merge', {
      id: 's1',
      targetId: null,
    });

    fireEvent.submit(document.getElementById('merge-sandbox-form')!);
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('merge-sandbox', {
        id: 's1',
        targetId: 'p1',
        workflowIds: ['w1'],
        deletedWorkflowIds: [],
        credentialIds: [],
        skippedCollectionNames: [],
      })
    );
  });

  test("shows the LiveView's merge refusal in the modal", async () => {
    const { pushEvent } = renderPage();
    pushEvent.mockResolvedValueOnce(preview).mockResolvedValueOnce({
      error: 'You are not authorized to merge into this project',
    });
    fireEvent.click(action('branch-rewire', 's1'));
    await screen.findByText('Workflows to merge');
    fireEvent.submit(document.getElementById('merge-sandbox-form')!);
    expect(
      await screen.findByText(
        'You are not authorized to merge into this project'
      )
    ).toBeInTheDocument();
    expect(screen.getByRole('dialog')).toBeInTheDocument();
  });
});
