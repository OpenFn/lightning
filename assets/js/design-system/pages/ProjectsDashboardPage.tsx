import DesignSystemProjectsDashboardPage from '@openfn/ui/pages/projects/ProjectsDashboardPage.tsx';
import type { ProjectOverview } from '@openfn/ui/types/workflows.ts';

import { designSystemPage } from '../page';

/** What DashboardLive.Index puts in `data-props`. */
interface Props {
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
