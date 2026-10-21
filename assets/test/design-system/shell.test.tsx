import { act, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, test, vi } from 'vitest';

import {
  mountShell,
  publishSidebar,
  Shell,
} from '../../js/design-system/shell';

// What a layout's SidebarBridge publishes (see LayoutComponents.sidebar_bridge).
const props = {
  variant: 'profile' as const,
  project: undefined,
  user: {
    firstName: 'Amy',
    lastName: 'Admin',
    email: 'amy@example.com',
    experimentalFeatures: false,
  },
  canAccessAdmin: false,
  sysInfo: true,
  adminEmail: 'support@openfn.org',
  releaseLabel: 'v2.19.2',
  theme: 'primary-theme' as const,
  collapsed: false,
};

const renderShell = (at: string, overrides: Partial<typeof props> = {}) => {
  window.history.replaceState(null, '', at);
  const navigate = vi.fn();
  const toggle = vi.fn();
  render(<Shell navigate={navigate} />);
  act(() => publishSidebar({ props: { ...props, ...overrides }, toggle }));
  return { navigate, toggle };
};

const href = (name: string) =>
  screen.getByRole('link', { name }).getAttribute('href');

describe('Shell', () => {
  afterEach(() => {
    window.history.replaceState(null, '', '/');
  });

  test('the profile menu links to your pages and marks the current one', () => {
    renderShell('/profile/tokens');

    expect(href('Projects')).toBe('/projects');
    expect(href('User Profile')).toBe('/profile');
    expect(href('Credentials')).toBe('/credentials');
    expect(href('API Tokens')).toBe('/profile/tokens');
    expect(screen.getByRole('link', { name: 'API Tokens' })).toHaveAttribute(
      'aria-current',
      'page'
    );
    for (const name of ['Documentation', 'Community', 'Support'])
      expect(screen.getByRole('link', { name })).toBeInTheDocument();
  });

  test('a superuser gets the admin links; the admin menu has its areas and Back', () => {
    renderShell('/settings/audit', {
      variant: 'admin',
      canAccessAdmin: true,
      theme: 'sudo-variant',
    });

    for (const name of [
      'Projects',
      'Users',
      'Authentication',
      'Audit',
      'Collections',
      'Maintenance',
      'Back',
    ])
      expect(screen.getByRole('link', { name })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Audit' })).toHaveAttribute(
      'aria-current',
      'page'
    );
    expect(href('Back')).toBe('/projects');
  });

  test('a project menu links to its areas', () => {
    renderShell('/projects/p1/history', {
      variant: 'project',
      project: { id: 'p1' },
    });

    expect(href('Workflows')).toBe('/projects/p1/w');
    expect(href('History')).toBe('/projects/p1/history');
    expect(href('Settings')).toBe('/projects/p1/settings');
    expect(screen.getByRole('link', { name: 'History' })).toHaveAttribute(
      'aria-current',
      'page'
    );
  });

  test('links navigate through LiveView and the toggle goes back to the page', async () => {
    const { navigate, toggle } = renderShell('/projects');

    await userEvent.click(screen.getByRole('link', { name: 'Credentials' }));
    await userEvent.click(
      screen.getByRole('button', { name: 'Toggle sidebar' })
    );

    expect(navigate).toHaveBeenCalledWith('/credentials', expect.anything());
    expect(toggle).toHaveBeenCalledTimes(1);
  });

  test('mounting takes over the first paint drawn by the server', async () => {
    window.history.replaceState(null, '', '/projects');
    document.body.innerHTML = `
      <div id="app-sidebar"><nav id="side-menu" data-first-paint>static</nav></div>
      <div id="sidebar-bridge" data-props='${JSON.stringify(props)}'></div>`;

    await act(async () => {
      mountShell({ execJS: vi.fn() });
      await Promise.resolve();
    });

    expect(document.querySelector('[data-first-paint]')).toBeNull();
    expect(document.querySelectorAll('#app-sidebar #side-menu')).toHaveLength(
      1
    );
    expect(screen.getByRole('link', { name: 'Credentials' })).toHaveAttribute(
      'href',
      '/credentials'
    );
    document.body.innerHTML = '';
  });

  test('the account menu says who is signed in and logs out', async () => {
    renderShell('/projects');

    await userEvent.click(screen.getByRole('button', { name: /Amy Admin/ }));

    expect(screen.getByText('Signed in as')).toBeInTheDocument();
    expect(screen.getByText('amy@example.com')).toBeInTheDocument();
    expect(screen.getByRole('menuitem', { name: 'Log out' })).toHaveAttribute(
      'href',
      '/users/log_out'
    );
  });
});
