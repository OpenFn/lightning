import type { NavigateOptions, Router } from '@openfn/ui/routing/router.tsx';
import { useMemo, useSyncExternalStore } from 'react';

// LiveView announces its own URL changes (patch, navigate, back and forward)
// with `phx:navigate`. Hash changes come from the browser.
const subscribe = (onChange: () => void) => {
  window.addEventListener('phx:navigate', onChange);
  window.addEventListener('hashchange', onChange);
  return () => {
    window.removeEventListener('phx:navigate', onChange);
    window.removeEventListener('hashchange', onChange);
  };
};

const useLocation = () => {
  const href = useSyncExternalStore(subscribe, () => window.location.href);
  return useMemo(() => new URL(href), [href]);
};

/**
 * A design system router that changes page through LiveView. `patch` is the
 * island's `navigate` prop: a patch to another LiveView's route falls back to
 * a live redirect, so it suits every in-app path. A jump to a `#hash` on this
 * page, or a link to another origin, is left to the browser.
 */
export const useLiveViewRouter = (
  patch: (path: string, opts?: NavigateOptions) => void
): Router =>
  useMemo(
    () => ({
      navigate: (to, opts) => {
        const url = new URL(to, window.location.href);
        const { origin, pathname, search } = window.location;
        const hashOnly =
          url.hash !== '' && url.pathname === pathname && url.search === search;

        if (url.origin !== origin || hashOnly) {
          if (opts?.replace) window.location.replace(url);
          else window.location.assign(url);
        } else {
          patch(`${url.pathname}${url.search}${url.hash}`, opts);
        }
      },
      useHref: to => to,
      useLocation,
    }),
    [patch]
  );
