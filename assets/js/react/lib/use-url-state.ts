import { produce } from 'immer';
import { useSyncExternalStore } from 'react';

interface URLState {
  params: Record<string, string>;
  hash: string;
}

// External store - created once, shared by all hook instances
class URLStore {
  private listeners = new Set<() => void>();
  private state: URLState = {
    params: Object.fromEntries(new URLSearchParams(window.location.search)),
    hash: window.location.hash.slice(1),
  };

  constructor() {
    this.setupListeners();
  }

  private setupListeners() {
    const updateParams = () => {
      const currentParams = Object.fromEntries(
        new URLSearchParams(window.location.search)
      );
      const currentHash = window.location.hash.slice(1);

      const newState = produce(this.state, draft => {
        // Remove params that no longer exist
        for (const key of Object.keys(draft.params)) {
          if (!(key in currentParams)) {
            delete draft.params[key];
          }
        }
        // Add/update params - Immer tracks if values actually changed
        for (const [key, value] of Object.entries(currentParams)) {
          draft.params[key] = value;
        }
        draft.hash = currentHash;
      });

      if (newState !== this.state) {
        this.state = newState;
        this.notifyListeners();
      }
    };

    // Monkey-patch history methods to detect URL changes from any source.
    // Note: If other libraries also patch these methods, execution order matters.
    const originalPushState = history.pushState.bind(history);
    const originalReplaceState = history.replaceState.bind(history);

    history.pushState = (...args) => {
      originalPushState(...args);
      updateParams();
    };

    history.replaceState = (...args) => {
      originalReplaceState(...args);
      updateParams();
    };

    window.addEventListener('popstate', updateParams);
    window.addEventListener('hashchange', updateParams);
  }

  private notifyListeners() {
    this.listeners.forEach(listener => listener());
  }

  /**
   * Subscribe to URL state changes.
   * Returns unsubscribe function.
   */
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  /**
   * Returns current URL state snapshot.
   */
  getSnapshot = () => this.state;

  // A fresh, mutable copy of the current URL. Writers seed from this and
  // override only the dimension they own (search or hash); everything else
  // carries over untouched.
  private currentURL = () => new URL(window.location.href);

  private urlsAreEquivalent = (a: URL, b: URL) => {
    if (a.pathname !== b.pathname || a.hash !== b.hash) return false;
    const ap = new URLSearchParams(a.search);
    ap.sort();
    const bp = new URLSearchParams(b.search);
    bp.sort();
    return ap.toString() === bp.toString();
  };

  // Skip no-op writes so mount-time normalization doesn't stack duplicate
  // browser history entries (a no-op pushState never notifies subscribers
  // anyway, due to the guard in updateParams). Param order is ignored so a
  // reorder-only write is also treated as a no-op.
  private pushIfChanged = (newURL: URL) => {
    if (this.urlsAreEquivalent(newURL, this.currentURL())) return;
    history.pushState({}, '', newURL);
  };

  /**
   * Update URL search params (merges with existing params).
   * Accepts strings, numbers, booleans; null removes param.
   */
  updateSearchParams = (
    updates: Record<string, string | number | boolean | null>
  ) => {
    const newURL = this.currentURL();

    Object.entries(updates).forEach(([key, value]) => {
      if (value === null) {
        newURL.searchParams.delete(key);
      } else {
        newURL.searchParams.set(key, String(value));
      }
    });

    this.pushIfChanged(newURL);
  };

  /**
   * Replace all URL search params (clears existing params).
   * Accepts strings, numbers, booleans; null skips param.
   */
  replaceSearchParams = (
    newParams: Record<string, string | number | boolean | null>
  ) => {
    const newURL = this.currentURL();
    newURL.search = '';
    Object.entries(newParams).forEach(([key, value]) => {
      if (value !== null) {
        newURL.searchParams.set(key, String(value));
      }
    });
    this.pushIfChanged(newURL);
  };

  /**
   * Update the URL hash fragment.
   * Pass null to remove hash.
   */
  updateHash = (hash: string | null) => {
    const newURL = this.currentURL();
    newURL.hash = hash ? `#${hash}` : '';
    this.pushIfChanged(newURL);
  };
}

// Single instance shared across all components
const urlStore = new URLStore();

// Export store for non-React code that needs URL updates
export { urlStore };

// Hook that uses the shared store
export function useURLState() {
  const snapshot = useSyncExternalStore(
    urlStore.subscribe,
    urlStore.getSnapshot,
    urlStore.getSnapshot // Server-side snapshot (same as client for this use case)
  );

  return {
    params: snapshot.params,
    hash: snapshot.hash,
    updateSearchParams: urlStore.updateSearchParams,
    replaceSearchParams: urlStore.replaceSearchParams,
    updateHash: urlStore.updateHash,
  };
}
