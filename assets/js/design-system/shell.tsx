import Sidebar, {
  type SidebarProps,
} from '@openfn/ui/components/shell/Sidebar.tsx';
import { RouterProvider } from '@openfn/ui/routing/router.tsx';
import { StrictMode, useSyncExternalStore } from 'react';
import { createRoot } from 'react-dom/client';

import type { PhoenixHook } from '#/hooks/PhoenixHook';

import { useLiveViewRouter } from './router';

/**
 * The shell: the design system's sidebar, mounted once from app.js into the
 * root layout so it survives LiveView navigation. Each LiveView's layout
 * renders a `SidebarBridge` element whose `data-props` say who is signed in
 * and where we are; the hook publishes them here, and sends the collapse
 * toggle back to that LiveView, which keeps the preference as before.
 */
type Props = Omit<SidebarProps, 'onToggle'>;

interface Bridge {
  props: Props;
  toggle: () => void;
}

let current: Bridge | null = null;
const listeners = new Set<() => void>();

/** Gives the shell a page's props; the bridge hook calls it on mount and update. */
export const publishSidebar = (bridge: Bridge) => {
  current = bridge;
  for (const listener of listeners) listener();
};
const publish = publishSidebar;

const subscribe = (listener: () => void) => {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
};

export const SidebarBridge = {
  mounted() {
    this.publish();
  },
  updated() {
    this.publish();
  },
  publish() {
    const props = parseProps(this.el);
    if (props)
      publish({
        props,
        toggle: () => {
          this.pushEvent('toggle_sidebar', {});
        },
      });
  },
} as PhoenixHook<{ publish(): void }>;

const parseProps = (el: HTMLElement): Props | null => {
  try {
    return JSON.parse(el.dataset['props'] ?? 'null') as Props | null;
  } catch (error) {
    console.error('Could not read the sidebar props', error);
    return null;
  }
};

type Go = (path: string, opts?: { replace?: boolean }) => void;

export const Shell = ({ navigate }: { navigate: Go }) => {
  const bridge = useSyncExternalStore(subscribe, () => current);
  // The sidebar belongs to no LiveView, so every link is a live redirect.
  const router = useLiveViewRouter({ navigate, redirect: navigate }, noRoutes);
  if (!bridge) return null;
  return (
    <RouterProvider value={router}>
      <Sidebar {...bridge.props} onToggle={bridge.toggle} />
    </RouterProvider>
  );
};

const noRoutes: string[] = [];

interface LiveNavigator {
  execJS(el: Element, encodedJS: string): void;
}

/** Mounts the shell into `#app-sidebar`, if the page has one. */
export const mountShell = (liveSocket: LiveNavigator) => {
  const el = document.getElementById('app-sidebar');
  if (!el) return;
  // The dead render already carries the bridge, so the sidebar is in the
  // first paint; the hook replaces these props, and the toggle, on join.
  const bridge = document.getElementById('sidebar-bridge');
  const props = bridge && parseProps(bridge);
  if (props) publish({ props, toggle: () => {} });
  const navigate: Go = (href, opts) => {
    const main = document.querySelector('[data-phx-main]') ?? el;
    liveSocket.execJS(
      main,
      JSON.stringify([['navigate', { href, replace: opts?.replace ?? false }]])
    );
  };
  createRoot(el).render(
    <StrictMode>
      <Shell navigate={navigate} />
    </StrictMode>
  );
};
