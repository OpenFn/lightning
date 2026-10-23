import {
  HistoryWorkOrdersPage as DesignSystemHistoryWorkOrdersPage,
  type HistoryWorkOrdersPageProps,
  type WorkOrderTarget,
} from '@openfn/ui';

import { designSystemPage } from '../page';

/** What RunLive.Index puts in `data-props` on the work orders tab: the page's props minus its handlers. */
export type Props = Omit<
  HistoryWorkOrdersPageProps,
  | 'onCheckRunLimit'
  | 'onCancelWorkOrder'
  | 'onRetryWorkOrder'
  | 'onCancelRun'
  | 'onRetryStep'
  | 'onBulkCancel'
  | 'onBulkRetry'
  | 'onExport'
>;

const bulk = (target: WorkOrderTarget) =>
  target === 'all'
    ? { type: 'all' }
    : { type: 'selected', workorder_ids: target };

/**
 * The design system's work orders page, fed by RunLive.Index's `:index`
 * action. The filters, the sort and the page are URL patches, which the
 * LiveView answers with new props; each action is one of its events, which
 * replies with a flash or an error.
 */
export const HistoryWorkOrdersPage = designSystemPage(
  'HistoryWorkOrdersPage',
  DesignSystemHistoryWorkOrdersPage,
  ['/projects/:project_id/history', '/projects/:project_id/history/channels'],
  (props: Props, { send }) => ({
    ...props,
    onCheckRunLimit: count => send('validate_bulk_rerun', { count }),
    onCancelWorkOrder: workOrderId =>
      send('cancel', { workorder_id: workOrderId }),
    onRetryWorkOrder: workOrderId =>
      send('bulk-rerun', { type: 'selected', workorder_ids: [workOrderId] }),
    onCancelRun: runId => send('cancel-run', { run_id: runId }),
    onRetryStep: (runId, stepId) =>
      send('rerun', { run_id: runId, step_id: stepId }),
    onBulkCancel: target => send('bulk-cancel', bulk(target)),
    onBulkRetry: (target, jobId) =>
      send('bulk-rerun', { ...bulk(target), job: jobId }),
    onExport: () => send('confirm-export'),
  })
);
