import { useSyncExternalStore } from "react";

// External store - created once, shared by all hook instances
class URLStore {
  private listeners = new Set<() => void>();
  private searchParams = new URLSearchParams(window.location.search);

  constructor() {
    this.setupListeners();
  }

  private setupListeners() {
    const updateParams = () => {
      const newParams = new URLSearchParams(window.location.search);
      if (this.searchParams.toString() !== newParams.toString()) {
        this.searchParams = newParams;
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

    window.addEventListener("popstate", updateParams);
  }

  private notifyListeners() {
    this.listeners.forEach((listener) => listener());
  }

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = () => this.searchParams;

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
    history.pushState({}, "", newURL);
  };
}

// Single instance shared across all components
const urlStore = new URLStore();

// Hook that uses the shared store
export function useURLState() {
  const searchParams = useSyncExternalStore(
    urlStore.subscribe,
    urlStore.getSnapshot,
    urlStore.getSnapshot, // Server-side snapshot (same as client for this use case)
  );

  return {
    searchParams,
    updateSearchParams: urlStore.updateSearchParams,
  };
}
