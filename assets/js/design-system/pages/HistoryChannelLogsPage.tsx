import DesignSystemHistoryChannelLogsPage, {
  type HistoryChannelLogsPageProps,
} from '@openfn/ui/pages/history/HistoryChannelLogsPage.tsx';

import { designSystemPage } from '../page';

/** What RunLive.Index puts in `data-props` on the channel logs tab: the page's props as they are. */
export type Props = HistoryChannelLogsPageProps;

/**
 * The design system's channel logs page, fed by RunLive.Index's
 * `:channel_logs` action. The filter and the page are URL patches, which
 * the LiveView answers with new props; the Work Orders tab is the same
 * LiveView's other action, so it patches too.
 */
export const HistoryChannelLogsPage = designSystemPage(
  'HistoryChannelLogsPage',
  DesignSystemHistoryChannelLogsPage,
  ['/projects/:project_id/history/channels', '/projects/:project_id/history'],
  (props: Props) => props
);
