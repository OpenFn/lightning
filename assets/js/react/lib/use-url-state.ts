import { produce } from 'immer';
import { useSyncExternalStore } from 'react';

interface URLState {
  searchParams: URLSearchParams;
  hash: string;
}

// External store - created once, shared by all hook instances
class URLStore {
  private listeners = new Set<() => void>();
  private state: URLState = {
    searchParams: new URLSearchParams(window.location.search),
    hash: window.location.hash.slice(1),
  };

  constructor() {
    this.setupListeners();
  }

  private setupListeners() {
    const updateParams = () => {
      const newSearchParams = new URLSearchParams(window.location.search);
      const newHash = window.location.hash.slice(1);

      const newState = produce(this.state, draft => {
        draft.searchParams = newSearchParams;
        draft.hash = newHash;
      });

      if (newState !== this.state) {
        this.state = newState;
        this.notifyListeners();
      }
    };

    // Monkey-patch history methods
    const originalPushState = history.pushState;
    const originalReplaceState = history.replaceState;

    history.pushState = (...args) => {
      originalPushState.apply(history, args);
      updateParams();
    };

    history.replaceState = (...args) => {
      originalReplaceState.apply(history, args);
      updateParams();
    };

    window.addEventListener('popstate', updateParams);
    window.addEventListener('hashchange', updateParams);
  }

  private notifyListeners() {
    this.listeners.forEach(listener => listener());
  }

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = () => this.state;

  updateSearchParams = (updates: Record<string, string | null>) => {
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
    newURL.hash = window.location.hash;
    history.pushState({}, '', newURL);
  };

  updateHash = (hash: string | null) => {
    const newURL =
      window.location.pathname +
      window.location.search +
      (hash ? `#${hash}` : '');
    history.pushState({}, '', newURL);
  };
}

// Single instance shared across all components
const urlStore = new URLStore();

// Hook that uses the shared store
export function useURLState() {
  const snapshot = useSyncExternalStore(
    urlStore.subscribe,
    urlStore.getSnapshot,
    urlStore.getSnapshot // Server-side snapshot (same as client for this use case)
  );

  return {
    searchParams: snapshot.searchParams,
    hash: snapshot.hash,
    updateSearchParams: urlStore.updateSearchParams,
    updateHash: urlStore.updateHash,
  };
}
