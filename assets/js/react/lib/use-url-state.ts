import { useEffect, useState, useCallback } from 'react';

export function useURLState() {
  const [searchParams, setSearchParams] = useState(
    () => new URLSearchParams(window.location.search)
  );

  // Listen for browser back/forward
  useEffect(() => {
    const handlePopState = () => {
      setSearchParams(new URLSearchParams(window.location.search));
    };

    window.addEventListener('popstate', handlePopState);
    return () => window.removeEventListener('popstate', handlePopState);
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
      window.history.pushState({}, '', newURL);
      setSearchParams(new URLSearchParams(newParams));
    },
    []
  );

  return { searchParams, updateSearchParams };
}
