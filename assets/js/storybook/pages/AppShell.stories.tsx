import type { Meta, StoryObj } from '@storybook/react-vite';

import {
  AppSidebar,
  TopBar,
  Breadcrumbs,
  Crumb,
  ProjectCrumb,
  PageFrame,
  ContentArea,
  Centered,
} from '../liveview/_shell';

/**
 * Composite view: the overall application shell — left sidebar + top bar +
 * scrollable content — assembled from the cloned layout parts
 * (live.html.heex + layout_components.ex `header/1`, `page_content/1`,
 * `centered/1`). Shows how the navigation, header and content region connect.
 */
const meta = {
  title: 'Pages/App Shell',
  tags: ['composite'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Default: Story = {
  render: () => (
    <PageFrame sidebar={<AppSidebar variant="project" activeItem="overview" />}>
      <TopBar
        actions={
          <button
            type="button"
            className="cursor-pointer rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-primary-500"
          >
            Create workflow
          </button>
        }
      >
        <Breadcrumbs>
          <ProjectCrumb label="openhie-demo" />
          <Crumb>Workflows</Crumb>
        </Breadcrumbs>
      </TopBar>
      <ContentArea>
        <Centered>
          <div className="rounded-lg border-2 border-dashed border-gray-300 bg-white/50 p-10 text-center">
            <span className="hero-square-3-stack-3d mx-auto block h-12 w-12 text-secondary-400" />
            <h3 className="mt-2 text-sm font-semibold text-gray-900">
              Page content renders here
            </h3>
            <p className="mt-1 text-sm text-gray-500">
              The sidebar (left), the top bar with breadcrumbs and actions, and
              this scrollable content region are the app shell every LiveView
              page is mounted inside.
            </p>
          </div>
        </Centered>
      </ContentArea>
    </PageFrame>
  ),
};
