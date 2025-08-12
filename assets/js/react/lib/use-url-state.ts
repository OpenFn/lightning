import { useCallback, useEffect, useState } from "react";

export function useURLState() {
  const [searchParams, setSearchParams] = useState(
    () => new URLSearchParams(window.location.search),
  );

  useEffect(() => {
    const updateParams = () => {
      const newParams = new URLSearchParams(window.location.search);
      setSearchParams((current) => {
        if (current.toString() !== newParams.toString()) {
          return newParams;
        }
        return current;
      });
    };

    // Listen for browser back/forward
    const handlePopState = updateParams;

    // Listen for programmatic navigation
    const handleNavigation = updateParams;

    // Monkey-patch history methods to dispatch custom events
    const originalPushState = history.pushState;
    const originalReplaceState = history.replaceState;

    history.pushState = (...args) => {
      originalPushState.apply(history, args);
      window.dispatchEvent(new Event('urlchange'));
    };

    history.replaceState = (...args) => {
      originalReplaceState.apply(history, args);
      window.dispatchEvent(new Event('urlchange'));
    };

    window.addEventListener("popstate", handlePopState);
    window.addEventListener("urlchange", handleNavigation);

    // Cleanup
    return () => {
      window.removeEventListener("popstate", handlePopState);
      window.removeEventListener("urlchange", handleNavigation);
      history.pushState = originalPushState;
      history.replaceState = originalReplaceState;
    };
  }, []);

  const updateSearchParams = useCallback(
    (updates: Record<string, string | null>) => {
      const newParams = new URLSearchParams(window.location.search);

      Object.entries(updates).forEach(([key, value]) => {
        if (value === null) {
          newParams.delete(key);
        } else {
          newParams.set(key, value);
        }
      });

      const newURL = new URL(window.location.pathname, window.location.origin);
      newURL.search = newParams.toString();
      history.pushState({}, "", newURL); // This will now trigger our custom event
    },
    [],
  );

  return { searchParams, updateSearchParams };
}