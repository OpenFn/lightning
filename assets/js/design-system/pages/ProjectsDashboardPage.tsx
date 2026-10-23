import {
  type ProjectOverview,
  ProjectsDashboardPage as DesignSystemProjectsDashboardPage,
} from '@openfn/ui';

import { designSystemPage } from '../page';

/** What DashboardLive.Index puts in `data-props`. */
export interface Props {
  firstName: string;
  projects: ProjectOverview[];
}

/** The design system's projects dashboard, fed by DashboardLive.Index. */
export const ProjectsDashboardPage = designSystemPage(
  'ProjectsDashboardPage',
  DesignSystemProjectsDashboardPage,
  ['/projects'],
  (props: Props, { send }) => ({
    ...props,
    // The page sends the url-safe name; the server derives it again.
    onCreate: ({ name, description }: { name: string; description: string }) =>
      send('create_project', { rawName: name, description }),
  })
);
