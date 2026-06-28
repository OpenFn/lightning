import type { Meta, StoryObj } from '@storybook/react-vite';

import { Showcase, Section } from '../_shared/showcase';

import { AppSidebar } from './_shell';

/**
 * The main left navigation sidebar (`#sidebar-panel` / `#side-menu`) from
 * lib/lightning_web/components/layouts/{live,settings}.html.heex +
 * layout_components.ex + menu.ex.
 *
 * This clone reuses the real element ids and classes, so the collapse/expand
 * width transition and the theme variants are driven by `app.css` itself — use
 * the chevron button at the bottom to collapse it. Each variant is its own
 * story because the app's CSS targets the `#sidebar-panel` / `#side-menu` ids
 * (only one per screen).
 */
function SidebarFrame({ children }: { children: React.ReactNode }) {
  return <div className="flex h-[600px] items-stretch bg-gray-50">{children}</div>;
}

const meta = {
  title: 'LiveView Clones/Sidebar (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const ProjectNav: Story = {
  name: 'Project sidebar',
  render: () => (
    <Showcase>
      <Section
        title="Project navigation"
        description="The in-project sidebar (Workflows / Sandboxes / History / Settings). Click the chevron at the bottom to collapse — width and label visibility transition via app.css."
      >
        <SidebarFrame>
          <AppSidebar variant="project" activeItem="overview" />
        </SidebarFrame>
      </Section>
    </Showcase>
  ),
};

export const SettingsNav: Story = {
  name: 'Instance settings sidebar',
  render: () => (
    <Showcase>
      <Section
        title="Instance settings navigation"
        description="The superuser settings sidebar (Projects / Users / Authentication / Audit / Collections / Back)."
      >
        <SidebarFrame>
          <AppSidebar variant="settings" activeItem="users" />
        </SidebarFrame>
      </Section>
    </Showcase>
  ),
};

export const ProfileNav: Story = {
  name: 'Profile sidebar',
  render: () => (
    <Showcase>
      <Section
        title="Profile navigation"
        description="The account sidebar (Projects / User Profile / Credentials / API Tokens)."
      >
        <SidebarFrame>
          <AppSidebar variant="profile" activeItem="profile" />
        </SidebarFrame>
      </Section>
    </Showcase>
  ),
};

export const SecondaryTheme: Story = {
  name: 'Theme · secondary (blue)',
  render: () => (
    <Showcase>
      <Section
        title="Secondary theme"
        description="The blue scope theme (#side-menu.secondary-variant)."
      >
        <SidebarFrame>
          <AppSidebar variant="project" theme="secondary" activeItem="runs" />
        </SidebarFrame>
      </Section>
    </Showcase>
  ),
};

export const SudoTheme: Story = {
  name: 'Theme · sudo (slate)',
  render: () => (
    <Showcase>
      <Section
        title="Sudo theme"
        description="The slate superuser theme (#side-menu.sudo-variant)."
      >
        <SidebarFrame>
          <AppSidebar variant="settings" theme="sudo" activeItem="audit" />
        </SidebarFrame>
      </Section>
    </Showcase>
  ),
};
