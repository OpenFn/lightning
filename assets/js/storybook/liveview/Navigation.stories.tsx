import type { Meta, StoryObj } from '@storybook/react-vite';
import { useState } from 'react';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clones of Lightning's server-rendered navigation chrome:
 *
 *   * `breadcrumbs/1`, `breadcrumb/1`, `breadcrumb_items/1` and
 *     `section_header/1` from `LightningWeb.LayoutComponents`
 *     (lib/lightning_web/components/layout_components.ex)
 *   * `menu_item/1`, `project_items/1` and `profile_items/1` from
 *     `LightningWeb.Components.Menu`
 *     (lib/lightning_web/live/components/menu.ex)
 *
 * Presentational only — `<.link navigate=...>`/`<.link patch=...>` become local
 * anchors/buttons and the `section_header` action `phx-click` is dropped. The
 * sidebar's colours come from the `#side-menu` CSS in assets/css/app.css
 * (`--primary-bg: indigo-800`, active item indigo-900/indigo-200, inactive
 * indigo-300); those are inlined as Tailwind classes here so the clone does not
 * depend on the `#side-menu` id selector.
 */

// --- breadcrumbs/1 + breadcrumb/1 -------------------------------------------
interface Crumb {
  label: string;
  href?: string;
}

function Breadcrumbs({ crumbs }: { crumbs: Crumb[] }) {
  return (
    <nav className="flex" aria-label="Breadcrumbs">
      <ol className="flex items-center space-x-2">
        {crumbs.map((crumb, index) => (
          <li key={crumb.label} className="breadcrumb-item">
            <div className="flex items-center">
              {index > 0 ? (
                <span className="hero-chevron-right mr-1 h-5 w-5 shrink-0 text-gray-400" />
              ) : null}
              {crumb.href ? (
                <a
                  href={crumb.href}
                  className="ml-1 flex text-sm font-medium text-gray-500 hover:text-gray-700"
                >
                  {crumb.label}
                </a>
              ) : (
                <span className="ml-1 flex items-center text-sm font-medium text-gray-500">
                  {crumb.label}
                </span>
              )}
            </div>
          </li>
        ))}
      </ol>
    </nav>
  );
}

// --- nav/1 ------------------------------------------------------------------
function Nav() {
  return (
    <nav className="bg-gray-800">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          <div className="flex items-center">
            <div className="flex-shrink-0">
              <div className="flex h-8 w-8 items-center justify-center rounded bg-white/10 text-xs font-bold text-white">
                Fn
              </div>
            </div>
          </div>
        </div>
      </div>
    </nav>
  );
}

// --- section_header/1 -------------------------------------------------------
function SectionHeader({
  title,
  subtitle,
  permissionsMessage,
  canPerformAction = true,
  actionButtonText,
}: {
  title: string;
  subtitle: string;
  permissionsMessage?: string;
  canPerformAction?: boolean;
  actionButtonText?: string;
}) {
  return (
    <div className="flex justify-between content-center">
      <div>
        <h6 className="font-medium text-black">{title}</h6>
        <small className="block my-1 text-xs text-gray-600">{subtitle}</small>
        {!canPerformAction && permissionsMessage ? (
          <small className="mt-2 text-red-700">
            Role based permissions: You cannot modify this project&apos;s{' '}
            {permissionsMessage}
          </small>
        ) : null}
      </div>
      {actionButtonText ? (
        <div className="sm:block" aria-hidden="true">
          <button
            type="button"
            className="inline-flex items-center rounded-md bg-indigo-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500"
          >
            {actionButtonText}
          </button>
        </div>
      ) : null}
    </div>
  );
}

// --- menu_item/1 + project_items/1 + profile_items/1 ------------------------
const MENU_ITEM_BASE =
  'menu-item h-10 rounded-lg text-sm font-medium flex items-center transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/30';
const MENU_ITEM_ACTIVE = 'text-indigo-200 bg-indigo-900';
const MENU_ITEM_INACTIVE = 'text-indigo-300 hover:bg-indigo-900';

function MenuItem({
  active = false,
  children,
}: {
  active?: boolean;
  children: ReactNode;
}) {
  return (
    <div className="h-10 mx-3 mb-1">
      <a
        href="#menu-item"
        aria-current={active ? 'page' : undefined}
        className={cn(
          MENU_ITEM_BASE,
          'px-3',
          active ? MENU_ITEM_ACTIVE : MENU_ITEM_INACTIVE
        )}
      >
        {children}
      </a>
    </div>
  );
}

type ProjectMenuItem =
  | 'overview'
  | 'channels'
  | 'sandboxes'
  | 'runs'
  | 'settings';

function ProjectItems({ active }: { active: ProjectMenuItem }) {
  return (
    <>
      <MenuItem active={active === 'overview'}>
        <span className="hero-square-3-stack-3d h-5 w-5 shrink-0" />
        <span className="menu-item-text ml-3 truncate">Workflows</span>
      </MenuItem>
      <MenuItem active={active === 'channels'}>
        <span className="hero-arrows-right-left h-5 w-5 shrink-0" />
        <span className="menu-item-text ml-3 truncate">Channels</span>
      </MenuItem>
      <MenuItem active={active === 'sandboxes'}>
        <span className="hero-beaker h-5 w-5 shrink-0" />
        <span className="menu-item-text ml-3 truncate">Sandboxes</span>
      </MenuItem>
      <MenuItem active={active === 'runs'}>
        <span className="hero-rectangle-stack h-5 w-5 shrink-0" />
        <span className="menu-item-text ml-3 truncate">History</span>
      </MenuItem>
      <MenuItem active={active === 'settings'}>
        <span className="hero-cog-8-tooth h-5 w-5 shrink-0" />
        <span className="menu-item-text ml-3 truncate">Settings</span>
      </MenuItem>
    </>
  );
}

type ProfileMenuItem = 'projects' | 'profile' | 'credentials' | 'tokens';

function ProfileItems({ active }: { active: ProfileMenuItem }) {
  return (
    <>
      <MenuItem active={active === 'projects'}>
        <span className="hero-folder h-5 w-5 shrink-0" />
        <span className="menu-item-text ml-3 truncate">Projects</span>
      </MenuItem>
      <MenuItem active={active === 'profile'}>
        <span className="hero-user-circle h-5 w-5 shrink-0" />
        <span className="menu-item-text ml-3 truncate">User Profile</span>
      </MenuItem>
      <MenuItem active={active === 'credentials'}>
        <span className="hero-key h-5 w-5 shrink-0" />
        <span className="menu-item-text ml-3 truncate">Credentials</span>
      </MenuItem>
      <MenuItem active={active === 'tokens'}>
        <span className="hero-command-line h-5 w-5 shrink-0" />
        <span className="menu-item-text ml-3 truncate">API Tokens</span>
      </MenuItem>
    </>
  );
}

/** Dark sidebar shell, mirroring the expanded `#side-menu` background. */
function SidebarFrame({ children }: { children: ReactNode }) {
  return (
    <div className="w-60 rounded-lg bg-indigo-800 py-3 text-white">
      {children}
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Navigation (LiveView Clone)',
  tags: ['useful'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Breadcrumbs_: Story = {
  name: 'Breadcrumbs',
  render: () => (
    <Showcase className="min-w-[560px]">
      <Section
        title="breadcrumbs/1 + breadcrumb_items/1"
        description="The breadcrumb trail shown in the top bar. The leading crumb has no chevron; intermediate crumbs link, and the final crumb is the current page."
      >
        <Breadcrumbs
          crumbs={[
            { label: 'Ministry of Health', href: '#project' },
            { label: 'History', href: '#history' },
            { label: 'Run a1b2c3' },
          ]}
        />
      </Section>
    </Showcase>
  ),
};

export const TopNav: Story = {
  name: 'Top nav bar',
  render: () => (
    <Showcase>
      <Section
        title="nav/1"
        description="The slim dark navigation bar with the OpenFn mark, used on unauthenticated and error pages."
      >
        <Nav />
      </Section>
    </Showcase>
  ),
};

export const SectionHeaders: Story = {
  name: 'Section header',
  render: () => (
    <Showcase className="min-w-[640px]">
      <Section
        title="section_header/1"
        description="A titled section heading with an optional action button and an optional role-based permissions notice."
      >
        <div className="flex flex-col gap-8 rounded-md border border-gray-200 bg-white p-6">
          <SectionHeader
            title="Collaborators"
            subtitle="People with access to this project"
            actionButtonText="Add collaborator"
          />
          <SectionHeader
            title="Webhook Security"
            subtitle="Restrict which requests can trigger this workflow"
            canPerformAction={false}
            permissionsMessage="webhook settings"
          />
        </div>
      </Section>
    </Showcase>
  ),
};

export const ProjectSidebar: Story = {
  name: 'Project sidebar menu',
  render: () => (
    <Showcase>
      <Section
        title="project_items/1"
        description="The per-project sidebar menu. The active item uses the darker indigo-900 background; inactive items lighten on hover."
      >
        <SidebarFrame>
          <ProjectItems active="overview" />
        </SidebarFrame>
      </Section>
    </Showcase>
  ),
};

export const ProfileSidebar: Story = {
  name: 'Profile sidebar menu',
  render: () => {
    const Demo = () => {
      const [active, setActive] = useState<ProfileMenuItem>('projects');
      const items: { id: ProfileMenuItem; label: string }[] = [
        { id: 'projects', label: 'Projects' },
        { id: 'profile', label: 'User Profile' },
        { id: 'credentials', label: 'Credentials' },
        { id: 'tokens', label: 'API Tokens' },
      ];
      return (
        <div className="flex items-start gap-6">
          <SidebarFrame>
            <ProfileItems active={active} />
          </SidebarFrame>
          <div className="flex flex-col gap-2">
            <span className="text-xs font-semibold tracking-wider text-gray-500 uppercase">
              Set active
            </span>
            {items.map(item => (
              <button
                key={item.id}
                type="button"
                onClick={() => {
                  setActive(item.id);
                }}
                className={cn(
                  'rounded-md px-3 py-1.5 text-left text-sm',
                  item.id === active
                    ? 'bg-indigo-100 text-indigo-700'
                    : 'text-gray-600 hover:bg-gray-100'
                )}
              >
                {item.label}
              </button>
            ))}
          </div>
        </div>
      );
    };
    return (
      <Showcase>
        <Section
          title="profile_items/1"
          description="The account-level sidebar menu (no project selected). Use the buttons to move the active highlight."
        >
          <Demo />
        </Section>
      </Showcase>
    );
  },
};
