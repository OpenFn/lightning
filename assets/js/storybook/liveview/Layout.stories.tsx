import type { Meta, StoryObj } from '@storybook/react-vite';
import { useState } from 'react';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clones of Lightning's layout chrome from
 * `LightningWeb.LayoutComponents`
 * (lib/lightning_web/components/layout_components.ex): `user_avatar/1`,
 * `user_menu_dropdown/1`, `header/1`, `centered/1` and `sidebar_footer/1`.
 *
 * Presentational only — the dropdown's `phx-click`/`phx-click-away` toggling is
 * replaced with local state, `<.link navigate=...>` items become anchors, and
 * the `toggle_sidebar` button is inert. `sidebar_footer` shows only the
 * expanded branding (the collapsed/expanded swap is driven by the `#side-menu`
 * CSS in app.css, which the clone does not depend on). Dark surfaces stand in
 * for the indigo-800 sidebar so the `bg-white/10` trigger reads correctly.
 */

// --- user_avatar/1 ----------------------------------------------------------
function UserAvatar({
  firstName,
  lastName,
  className,
}: {
  firstName: string;
  lastName?: string | undefined;
  className?: string;
}) {
  const initials = (
    firstName.charAt(0) + (lastName ? lastName.charAt(0) : '')
  ).toUpperCase();
  return (
    <div
      className={cn(
        'h-5 w-5 rounded-full bg-gray-100 flex items-center justify-center text-[10px] font-semibold text-gray-500',
        className
      )}
    >
      {initials}
    </div>
  );
}

// --- user_menu_dropdown/1 ---------------------------------------------------
interface MockUser {
  firstName: string;
  lastName?: string;
  email: string;
}

function UserMenuDropdown({ user }: { user: MockUser }) {
  const [open, setOpen] = useState(false);
  const fullName = `${user.firstName}${user.lastName ? ` ${user.lastName}` : ''}`;
  const links: { label: string; icon: string }[] = [
    { label: 'Projects', icon: 'hero-folder' },
    { label: 'User Profile', icon: 'hero-user-circle' },
    { label: 'Credentials', icon: 'hero-key' },
    { label: 'API Tokens', icon: 'hero-command-line' },
  ];
  return (
    <div className="h-10 mx-3 flex-1 min-w-0 relative">
      <button
        type="button"
        aria-haspopup="true"
        aria-expanded={open}
        onClick={() => {
          setOpen(value => !value);
        }}
        className="menu-item h-10 w-full bg-white/10 hover:bg-white/20 rounded-lg text-sm font-medium flex items-center transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/30 px-3"
      >
        <div className="flex items-center w-full min-w-0">
          <UserAvatar
            firstName={user.firstName}
            lastName={user.lastName}
            className="shrink-0"
          />
          <div className="min-w-0 overflow-hidden flex-1 ml-3">
            <div className="text-sm font-medium text-white truncate">
              {fullName}
            </div>
          </div>
          <span className="hero-chevron-down w-4 h-4 text-white/70 shrink-0" />
        </div>
      </button>
      {open ? (
        <div
          className="absolute z-50 mt-2 w-56 origin-top-left divide-y divide-gray-100 rounded-md bg-white shadow-lg outline-1 outline-black/5"
          role="menu"
          aria-orientation="vertical"
        >
          <div className="px-4 py-3">
            <p className="text-sm text-gray-700">Signed in as</p>
            <p className="truncate text-sm font-medium text-gray-900">
              {user.email}
            </p>
          </div>
          <div className="py-1">
            {links.map(link => (
              <a
                key={link.label}
                href="#user-menu"
                role="menuitem"
                className="flex items-center px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900"
              >
                <span className={cn(link.icon, 'h-5 w-5 inline-block mr-2')} />
                {link.label}
              </a>
            ))}
          </div>
          <div className="py-1">
            <a
              href="#log-out"
              role="menuitem"
              className="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900"
            >
              Log out
            </a>
          </div>
        </div>
      ) : null}
    </div>
  );
}

// --- header/1 ---------------------------------------------------------------
function Header({
  title,
  children,
}: {
  title?: ReactNode;
  children?: ReactNode;
}) {
  return (
    <div className="flex-none bg-white shadow-xs border-b border-gray-200">
      <div className="max-w-7xl mx-auto sm:px-6 lg:px-8 py-6 flex items-center h-20">
        {title ? (
          <h1 className="text-gray-900 flex items-center text-xl font-semibold">
            {title}
          </h1>
        ) : null}
        <div className="grow" />
        {children}
      </div>
    </div>
  );
}

// --- centered/1 -------------------------------------------------------------
function Centered({
  className,
  children,
}: {
  className?: string;
  children: ReactNode;
}) {
  return (
    <div className={cn('max-w-7xl mx-auto py-6 sm:px-6 lg:px-8', className)}>
      {children}
    </div>
  );
}

// --- sidebar_footer/1 -------------------------------------------------------
function OpenFnLogo({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 2185 800"
      className={className}
      fill="currentColor"
      aria-label="OpenFn"
      xmlns="http://www.w3.org/2000/svg"
    >
      <g transform="translate(2093.4261,112.28066)">
        <g transform="translate(-846.97982)">
          <path
            d="M 136.21805,-92.133614 H 895.92398 V 667.57232 H 136.21805 Z"
            fillOpacity="0"
            stroke="currentColor"
            strokeWidth="40.2941"
          />
          <path d="m 271.68852,467.23065 h 69.5073 V 322.19209 H 472.7963 V 260.0989 H 341.19582 V 180.86058 H 476.03998 V 118.7674 H 271.68852 Z m 403.1422,0 h 66.72701 V 305.51034 c 0,-45.87482 -25.94939,-82.94538 -83.40876,-82.94538 -26.87615,0 -50.50864,8.80426 -70.43406,37.53394 h -0.92677 v -31.04659 h -63.94671 v 238.17834 h 66.72701 V 331.92311 c 0,-32.43674 16.68175,-55.60584 43.5579,-55.60584 20.85219,0 41.70438,11.58455 41.70438,45.87482 z" />
        </g>
        <path d="m -1788.7957,292.9783 c 0,62.55657 -32.4367,118.62579 -97.3102,118.62579 -64.8735,0 -97.3102,-56.06922 -97.3102,-118.62579 0,-62.55657 32.4367,-118.62579 97.3102,-118.62579 64.8735,0 97.3102,56.06922 97.3102,118.62579 z m -266.908,0 c 0,93.60316 61.1664,180.71898 169.5978,180.71898 108.4314,0 169.5978,-87.11582 169.5978,-180.71898 0,-93.60316 -61.1664,-180.71897 -169.5978,-180.71897 -108.4314,0 -169.5978,87.11581 -169.5978,180.71897 z" />
      </g>
    </svg>
  );
}

function SidebarFooter() {
  return (
    <div className="flex-shrink-0 flex flex-col border-t border-white/10 pt-3 mt-3">
      <div className="h-14 text-center">
        <div className="pt-2">
          <OpenFnLogo className="h-6 text-indigo-300 mx-auto" />
        </div>
        <div className="text-[8px] text-indigo-300 opacity-50 flex justify-center">
          <code className="py-1 rounded-md break-keep inline-block align-middle text-center">
            v2.14.0
          </code>
        </div>
      </div>
      <div className="border-t border-white/10 mt-2">
        <button
          type="button"
          title="Toggle sidebar"
          aria-label="Toggle sidebar"
          className="w-full py-1.5 focus:outline-none cursor-pointer hover:bg-white/5 transition-colors"
        >
          <div className="mx-3 flex items-center h-5 pl-3">
            <svg
              className="w-5 h-5 text-white/70"
              viewBox="0 0 18 18"
              fill="currentColor"
              aria-hidden="true"
            >
              <path
                fillRule="evenodd"
                d="M5.46 8.846l3.444-3.442-1.058-1.058-4.5 4.5 4.5 4.5 1.058-1.057L5.46 8.84zm7.194 4.5v-9h-1.5v9h1.5z"
              />
            </svg>
          </div>
        </button>
      </div>
    </div>
  );
}

/** Dark surface so the translucent dropdown trigger / footer read correctly. */
function DarkPanel({
  className,
  children,
}: {
  className?: string;
  children: ReactNode;
}) {
  return (
    <div className={cn('rounded-lg bg-indigo-800 py-3 text-white', className)}>
      {children}
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Layout (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Avatars: Story = {
  name: 'User avatar',
  render: () => (
    <Showcase>
      <Section
        title="user_avatar/1"
        description="A small circular badge showing the user's uppercased initials. Falls back to a single initial when there is no last name."
      >
        <div className="flex items-center gap-4">
          <UserAvatar firstName="Amara" lastName="Okafor" />
          <UserAvatar firstName="Liang" />
          <UserAvatar firstName="Sofia" lastName="Reyes" className="h-8 w-8 text-sm" />
        </div>
      </Section>
    </Showcase>
  ),
};

export const UserMenu: Story = {
  name: 'User menu dropdown',
  render: () => (
    <Showcase>
      <Section
        title="user_menu_dropdown/1"
        description="The account switcher at the foot of the sidebar. Click the trigger to toggle the menu (closes on a second click)."
      >
        <DarkPanel className="w-64">
          <UserMenuDropdown
            user={{
              firstName: 'Amara',
              lastName: 'Okafor',
              email: 'amara.okafor@health.gov',
            }}
          />
        </DarkPanel>
      </Section>
    </Showcase>
  ),
};

export const PageHeader: Story = {
  name: 'Header + centered',
  render: () => (
    <Showcase>
      <Section
        title="header/1 + centered/1"
        description="The white top bar (with a title and a trailing action slot) above a width-constrained, centered content region."
      >
        <div className="bg-gray-100">
          <Header
            title="Workflows"
            children={
              <button
                type="button"
                className="inline-flex items-center rounded-md bg-indigo-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500"
              >
                New workflow
              </button>
            }
          />
          <Centered>
            <div className="rounded-md border border-gray-200 bg-white p-6 text-sm text-gray-700">
              Page content renders here, capped at max-w-7xl and centered.
            </div>
          </Centered>
        </div>
      </Section>
    </Showcase>
  ),
};

export const Footer: Story = {
  name: 'Sidebar footer',
  render: () => (
    <Showcase>
      <Section
        title="sidebar_footer/1"
        description="The branding + collapse control pinned to the bottom of the sidebar (expanded state shown)."
      >
        <DarkPanel className="w-60 px-3">
          <SidebarFooter />
        </DarkPanel>
      </Section>
    </Showcase>
  ),
};
