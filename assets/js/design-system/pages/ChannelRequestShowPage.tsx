import {
  ChannelRequestShowPage as DesignSystemChannelRequestShowPage,
  type ChannelRequestShowPageProps,
} from '@openfn/ui';

import { designSystemPage } from '../page';

/** What ChannelRequestLive.Show puts in `data-props`: the page's props as they are. */
export type Props = ChannelRequestShowPageProps;

/** The design system's channel request page, fed by ChannelRequestLive.Show. It has no events. */
export const ChannelRequestShowPage = designSystemPage(
  'ChannelRequestShowPage',
  DesignSystemChannelRequestShowPage,
  ['/projects/:project_id/history/channels/:id'],
  (props: Props) => props
);
