import {
  type ChannelFormValues,
  ChannelsIndexPage as DesignSystemChannelsIndexPage,
  type ChannelsIndexPageProps,
} from '@openfn/ui';

import { designSystemPage } from '../page';

/** What ChannelLive.Index puts in `data-props`. */
export type Props = Omit<
  ChannelsIndexPageProps,
  'onToggle' | 'onDelete' | 'onSave'
>;

/** The design system's channels page, fed by ChannelLive.Index. */
export const ChannelsIndexPage = designSystemPage(
  'ChannelsIndexPage',
  DesignSystemChannelsIndexPage,
  [
    '/projects/:project_id/channels',
    '/projects/:project_id/channels/new',
    '/projects/:project_id/channels/:id/edit',
  ],
  (props: Props, { send }) => ({
    ...props,
    // The same events and payloads the HEEx page sent; the server answers
    // each with a flash and a fresh list, or rejects.
    onToggle: (id: string, enabled: boolean) =>
      send('toggle_channel_state', {
        channel_state: String(enabled),
        value_key: id,
      }),
    onDelete: (id: string) => send('delete_channel', { id }),
    // The server knows whether the open form creates or edits.
    onSave: (values: ChannelFormValues) => send('save_channel', { ...values }),
  })
);
