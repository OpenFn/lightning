import { useState } from 'react';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

/**
 * Reusable clones of the app layout shell, used by the Sidebar story and the
 * composite "Pages" stories. These deliberately reuse the REAL element ids and
 * classes from the app (`#sidebar-panel`, `#side-menu`, `.menu-item`,
 * `.menu-item-active`, `.app-logo-container`, `.sidebar-footer`, …) so the
 * collapse/expand width transitions and theme variants come straight from
 * `app.css` — the clone is driven by the production stylesheet.
 *
 * Sources: lib/lightning_web/components/layouts/{live,settings}.html.heex,
 * lib/lightning_web/components/layout_components.ex,
 * lib/lightning_web/live/components/menu.ex.
 */
export type SidebarVariant = 'project' | 'settings' | 'profile';
export type SidebarTheme = 'default' | 'secondary' | 'sudo';

interface MenuLink {
  key: string;
  label: string;
  icon: string;
}

const PROJECT_ITEMS: MenuLink[] = [
  { key: 'overview', label: 'Workflows', icon: 'hero-square-3-stack-3d' },
  { key: 'sandboxes', label: 'Sandboxes', icon: 'hero-beaker' },
  { key: 'runs', label: 'History', icon: 'hero-rectangle-stack' },
  { key: 'settings', label: 'Settings', icon: 'hero-cog-8-tooth' },
];

const PROJECT_FOOTER_ITEMS: MenuLink[] = [
  { key: 'docs', label: 'Documentation', icon: 'hero-book-open-mini' },
  { key: 'community', label: 'Community', icon: 'hero-user-group-mini' },
  { key: 'support', label: 'Support', icon: 'hero-lifebuoy-mini' },
];

const SETTINGS_ITEMS: MenuLink[] = [
  { key: 'projects', label: 'Projects', icon: 'hero-building-library' },
  { key: 'users', label: 'Users', icon: 'hero-user-group' },
  { key: 'authentication', label: 'Authentication', icon: 'hero-key' },
  { key: 'audit', label: 'Audit', icon: 'hero-archive-box' },
  { key: 'collections', label: 'Collections', icon: 'hero-circle-stack' },
];

const PROFILE_ITEMS: MenuLink[] = [
  { key: 'projects', label: 'Projects', icon: 'hero-folder' },
  { key: 'profile', label: 'User Profile', icon: 'hero-user-circle' },
  { key: 'credentials', label: 'Credentials', icon: 'hero-key' },
  { key: 'tokens', label: 'API Tokens', icon: 'hero-command-line' },
];

const VARIANT_ITEMS: Record<SidebarVariant, MenuLink[]> = {
  project: PROJECT_ITEMS,
  settings: SETTINGS_ITEMS,
  profile: PROFILE_ITEMS,
};

const THEME_CLASS: Record<SidebarTheme, string> = {
  default: '',
  secondary: 'secondary-variant',
  sudo: 'sudo-variant',
};

function MenuItem({
  item,
  active,
  onSelect,
}: {
  item: MenuLink;
  active: boolean;
  onSelect: () => void;
}) {
  return (
    <div className="mx-3 mb-1 h-10">
      <button
        type="button"
        onClick={onSelect}
        aria-current={active ? 'page' : undefined}
        className={cn(
          'menu-item flex h-10 w-full items-center rounded-lg text-sm font-medium transition-colors duration-150',
          active ? 'menu-item-active' : 'menu-item-inactive'
        )}
      >
        <span className={cn(item.icon, 'h-5 w-5 shrink-0')} />
        <span className="menu-item-text truncate">{item.label}</span>
      </button>
    </div>
  );
}

function SidebarFooter() {
  return (
    <div className="sidebar-footer flex shrink-0 flex-col border-t border-white/10 pt-3">
      <div className="sidebar-branding-expanded h-14 text-center">
        <div className="primary-light pt-2 text-sm font-semibold tracking-wide">
          openfn
        </div>
        <span className="text-[11px] text-white/50">v2.14.0</span>
      </div>
      <div className="sidebar-branding-collapsed hidden h-14 text-center">
        <div className="primary-light pt-2 text-sm font-semibold">OF</div>
      </div>
    </div>
  );
}

export function AppSidebar({
  variant = 'project',
  theme = 'default',
  activeItem,
}: {
  variant?: SidebarVariant;
  theme?: SidebarTheme;
  activeItem?: string;
}) {
  const items = VARIANT_ITEMS[variant];
  const [active, setActive] = useState(activeItem ?? items[0]?.key ?? '');
  const [collapsed, setCollapsed] = useState(false);
  const themeClass = THEME_CLASS[theme];

  return (
    <div
      id="sidebar-panel"
      data-collapsed={String(collapsed)}
      className="group flex h-full flex-col transition-[width] duration-200"
    >
      <div
        className={cn('app-logo-container flex h-20 items-center', themeClass)}
      >
        <div className="user-menu-trigger menu-item menu-item-inactive mx-3 flex h-10 w-full items-center rounded-lg bg-white/10 text-sm font-medium">
          <span className="hero-user-circle h-5 w-5 shrink-0 text-white" />
          <span className="user-menu-text ml-2 min-w-0 flex-1 truncate text-white">
            Amara Okafor
          </span>
          <span className="hero-chevron-down user-menu-chevron h-4 w-4 shrink-0 text-white/70" />
        </div>
      </div>

      <nav id="side-menu" className={cn('flex-1 overflow-hidden', themeClass)}>
        <div className="flex h-full flex-col">
          <div className="flex min-h-0 flex-1 flex-col overflow-y-auto py-4">
            {items.map(item => (
              <MenuItem
                key={item.key}
                item={item}
                active={active === item.key}
                onSelect={() => {
                  setActive(item.key);
                }}
              />
            ))}
            <div className="grow" />
            {variant === 'project'
              ? PROJECT_FOOTER_ITEMS.map(item => (
                  <MenuItem
                    key={item.key}
                    item={item}
                    active={false}
                    onSelect={() => {
                      setActive(item.key);
                    }}
                  />
                ))
              : null}
            {variant === 'settings' ? (
              <MenuItem
                item={{ key: 'back', label: 'Back', icon: 'hero-arrow-left' }}
                active={false}
                onSelect={() => {
                  setActive('back');
                }}
              />
            ) : null}
          </div>
          <SidebarFooter />
          <div className="border-t border-white/10">
            <button
              type="button"
              onClick={() => {
                setCollapsed(value => !value);
              }}
              className="sidebar-toggle-btn w-full cursor-pointer py-1.5 transition-colors hover:bg-white/5 focus:outline-none"
              aria-label="Toggle sidebar"
            >
              <div className="mx-3 flex h-5 items-center pl-3">
                <span className="hero-chevron-double-left h-5 w-5 text-white/70" />
              </div>
            </button>
          </div>
        </div>
      </nav>
    </div>
  );
}

/** The top bar from `LayoutComponents.header/1`. */
export function TopBar({
  children,
  actions,
}: {
  children: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <div
      className="flex-none border-b border-gray-200 bg-white shadow-xs"
      data-testid="top-bar"
    >
      <div className="mx-auto flex h-20 max-w-7xl items-center py-6 sm:px-6 lg:px-8">
        {children}
        <div className="grow" />
        {actions}
      </div>
    </div>
  );
}

/** Breadcrumb wrapper + crumb, from `LayoutComponents.breadcrumbs/1`. */
export function Breadcrumbs({ children }: { children: ReactNode }) {
  return (
    <nav className="flex" aria-label="Breadcrumbs">
      <ol className="flex items-center space-x-2">{children}</ol>
    </nav>
  );
}

export function Crumb({
  children,
  withSeparator = true,
}: {
  children: ReactNode;
  withSeparator?: boolean;
}) {
  return (
    <li className="breadcrumb-item">
      <div className="flex items-center">
        {withSeparator ? (
          <span className="hero-chevron-right mr-1 h-5 w-5 shrink-0 text-gray-400" />
        ) : null}
        <span className="ml-1 flex items-center text-sm font-medium text-gray-500">
          {children}
        </span>
      </div>
    </li>
  );
}

/** A project breadcrumb pill (clone of the PickerButton trigger look). */
export function ProjectCrumb({ label }: { label: string }) {
  return (
    <li className="mr-3">
      <span className="inline-flex items-center gap-1.5 rounded-md bg-gray-100 px-2 py-1 text-sm font-medium text-gray-700 ring-1 ring-gray-300 ring-inset">
        <span className="hero-folder h-4 w-4 text-gray-500" />
        {label}
        <span className="hero-chevron-down h-4 w-4 text-gray-400" />
      </span>
    </li>
  );
}

/**
 * Composite page frame: sidebar + (top bar + scrollable content), mirroring the
 * `flex flex-row h-full` layout in live.html.heex and `page_content/1`.
 */
export function PageFrame({
  sidebar,
  children,
}: {
  sidebar: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="flex h-[680px] w-full flex-row overflow-hidden bg-white">
      {sidebar}
      <div className="flex h-full flex-auto flex-col">{children}</div>
    </div>
  );
}

/** Scrollable content region with the app's gray background. */
export function ContentArea({ children }: { children: ReactNode }) {
  return (
    <div className="relative flex-auto bg-secondary-100">
      <section className="absolute inset-0 overflow-y-auto">{children}</section>
    </div>
  );
}

export function Centered({ children }: { children: ReactNode }) {
  return (
    <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">{children}</div>
  );
}
