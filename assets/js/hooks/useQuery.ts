import { useMemo } from 'react';

function useQuery<const T extends readonly string[]>(
  queries: T
): { [K in T[number]]?: string } {
  return useMemo(() => {
    const q = new URLSearchParams(window.location.search);
    const result: Partial<Record<T[number], string>> = {};
    for (const key of queries) {
      const value = q.get(key);
      if (value !== null) result[key as T[number]] = value;
    }
    return result as { [K in T[number]]?: string };
  }, [window.location.search, ...queries]);
}

export default useQuery;
