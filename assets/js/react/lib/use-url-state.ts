import { useCallback, useEffect, useState } from "react";

export function useURLState() {
  const [searchParams, setSearchParams] = useState(
    () => new URLSearchParams(window.location.search),
  );

  // Listen for browser back/forward
  useEffect(() => {
    const handlePopState = () => {
      const newParams = new URLSearchParams(window.location.search);
      setSearchParams((current) => {
        // Only update if the params actually changed
        if (current.toString() !== newParams.toString()) {
          return newParams;
        }
        return current;
      });
    };

    window.addEventListener("popstate", handlePopState);
    return () => window.removeEventListener("popstate", handlePopState);
  }, []);

  // Update URL without page refresh
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
      window.history.pushState({}, "", newURL);

      setSearchParams((current) => {
        // Only update if the params actually changed
        if (current.toString() !== newParams.toString()) {
          return newParams;
        }
        return current;
      });
    },
    [],
  );

  return { searchParams, updateSearchParams };
}
