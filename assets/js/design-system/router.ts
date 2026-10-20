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

type Go = (path: string, opts?: NavigateOptions) => void;

/**
 * A design system router that changes page through LiveView. Paths under
 * `ownPath` belong to this LiveView, so they patch (the island's `navigate`).
 * Anything else is a live redirect (`redirect`), which falls back to a full
 * page load when the target isn't a LiveView; a patch there would crash.
 * A jump to a `#hash` on this page, or a link to another origin, is left to
 * the browser.
 */
export const useLiveViewRouter = (
  { navigate, redirect }: { navigate: Go; redirect: Go },
  ownPath: string
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
          const own =
            url.pathname === ownPath || url.pathname.startsWith(`${ownPath}/`);
          (own ? navigate : redirect)(
            `${url.pathname}${url.search}${url.hash}`,
            opts
          );
        }
      },
      useHref: to => to,
      useLocation,
    }),
    [navigate, redirect, ownPath]
  );
