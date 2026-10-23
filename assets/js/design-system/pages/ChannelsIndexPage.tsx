import DesignSystemChannelsIndexPage from '@openfn/ui/pages/projects/ChannelsIndexPage.tsx';
import type {
  ChannelForm,
  ChannelFormValues,
  ChannelRow,
} from '@openfn/ui/types/channels.ts';
import type { Project } from '@openfn/ui/types/projects.ts';

import { designSystemPage } from '../page';

/** What ChannelLive.Index puts in `data-props`. */
export interface Props {
  project: Pick<Project, 'id' | 'parentId' | 'color'>;
  projectLabel: string;
  channels: ChannelRow[];
  totalChannels: number;
  totalRequests: number;
  logsHref: string;
  canCreateChannel: boolean;
  canEditChannel: boolean;
  canDeleteChannel: boolean;
  /** Set while the route has the form open; the LiveView loads its options then. */
  form: ChannelForm | null;
}

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
