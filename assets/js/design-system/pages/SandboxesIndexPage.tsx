import {
  type MergePreviewResult,
  SandboxesIndexPage as DesignSystemSandboxesIndexPage,
  type SandboxesIndexPageProps,
} from '@openfn/ui';

import { designSystemPage } from '../page';

/** What SandboxLive.Index puts in `data-props`: the page's props minus its handlers. */
export type Props = Omit<
  SandboxesIndexPageProps,
  | 'onCloseForm'
  | 'onCreateSandbox'
  | 'onUpdateSandbox'
  | 'onDeleteSandbox'
  | 'onCancelDeletion'
  | 'onPreviewMerge'
  | 'onMergeSandbox'
>;

/**
 * The design system's sandboxes page, fed by SandboxLive.Index. The create
 * and edit forms are routes, which the LiveView answers with `form`; each
 * action is one of its events, which re-checks the id against the tree it
 * showed and replies with a flash or an error.
 */
export const SandboxesIndexPage = designSystemPage(
  'SandboxesIndexPage',
  DesignSystemSandboxesIndexPage,
  [
    '/projects/:project_id/sandboxes',
    '/projects/:project_id/sandboxes/new',
    '/projects/:project_id/sandboxes/:id/edit',
  ],
  (props: Props, { send, request, navigate }) => ({
    ...props,
    onCloseForm: () => navigate(`/projects/${props.project.id}/sandboxes`),
    onCreateSandbox: values => send('create-sandbox', { ...values }),
    onUpdateSandbox: (id, values) => send('update-sandbox', { id, ...values }),
    onDeleteSandbox: (id, nameConfirmation) =>
      send('delete-sandbox', { id, nameConfirmation }),
    onCancelDeletion: id => send('cancel-sandbox-deletion', { id }),
    onPreviewMerge: (id, targetId) =>
      request<MergePreviewResult>('preview-merge', { id, targetId }),
    onMergeSandbox: (id, values) => send('merge-sandbox', { id, ...values }),
  })
);
