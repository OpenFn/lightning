import { useContext, useMemo, useSyncExternalStore } from 'react';

import { StoreContext } from '../contexts/StoreProvider';
import { extractAdaptorName, extractPackageName } from '../utils/adaptorUtils';

interface AdaptorIconProps {
  name: string;
  size?: 'sm' | 'md' | 'lg';
}

const sizeClasses = {
  sm: 'h-5 w-5',
  md: 'h-8 w-8',
  lg: 'h-12 w-12',
};

// Reads the icon URL directly from StoreContext instead of via the
// useAdaptorIconUrl hook in hooks/useAdaptors, so tests that mock that whole
// module (e.g. FullScreenIDE) fall back to the placeholder instead of
// crashing on a missing export.
function useStoreIconUrl(name: string): string | null {
  const context = useContext(StoreContext);
  const adaptorStore = context?.adaptorStore ?? null;
  const packageName = extractPackageName(name);

  const selectIconUrl = useMemo(() => {
    if (!adaptorStore) return () => null;
    return adaptorStore.withSelector(state => {
      const found = state.adaptors.find(a => a.name === packageName);
      return found?.icon_urls?.square ?? null;
    });
  }, [adaptorStore, packageName]);

  const noopSubscribe = useMemo(() => () => () => {}, []);

  return useSyncExternalStore(
    adaptorStore?.subscribe ?? noopSubscribe,
    selectIconUrl
  );
}

export function AdaptorIcon({ name, size = 'md' }: AdaptorIconProps) {
  const displayName = extractAdaptorName(name) ?? null;
  const iconUrl = useStoreIconUrl(name);

  if (!displayName) {
    return (
      <div
        className={`${sizeClasses[size]} rounded-md bg-gray-200
        flex items-center justify-center`}
      >
        <span className="text-xs font-semibold text-gray-500">
          {displayName?.[0]?.toUpperCase() || '?'}
        </span>
      </div>
    );
  }

  if (!iconUrl) {
    return (
      <div
        className={`${sizeClasses[size]} rounded-md bg-gray-200
        flex items-center justify-center`}
      >
        <span className="text-xs font-semibold text-gray-500">
          {displayName[0].toUpperCase() || '?'}
        </span>
      </div>
    );
  }

  return (
    <img
      src={iconUrl}
      alt={displayName}
      className={`${sizeClasses[size]} object-cover`}
    />
  );
}
