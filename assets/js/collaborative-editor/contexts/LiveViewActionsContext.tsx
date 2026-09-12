import { createContext, useContext } from 'react';

interface LiveViewActions {
  pushEvent: (name: string, payload: Record<string, unknown>) => void;
  pushEventTo: (
    name: string,
    payload: Record<string, unknown>,
    callback?: (response: unknown) => void
  ) => void;
  handleEvent: (
    name: string,
    callback: (payload: unknown) => void
  ) => () => void;
  navigate: (path: string, options?: { replace?: boolean }) => void;
  /**
   * A live navigation rather than a patch: it remounts the LiveView, so every
   * mount hook runs again. Use it for anything that changes which project the
   * editor is in, because the project scope and the workflow-ownership check
   * are mount hooks and a patch would not re-run them.
   */
  redirect: (path: string, options?: { replace?: boolean }) => void;
}

const LiveViewActionsContext = createContext<LiveViewActions | null>(null);

export interface LiveViewActionsProviderProps {
  children: React.ReactNode;
  actions: LiveViewActions;
}

export function LiveViewActionsProvider({
  children,
  actions,
}: LiveViewActionsProviderProps) {
  return (
    <LiveViewActionsContext.Provider value={actions}>
      {children}
    </LiveViewActionsContext.Provider>
  );
}

/**
 * The actions if there is a LiveView to ask, or null.
 *
 * For components that are mounted whether or not one is present and have
 * something sensible to do without it. Everything else should use
 * `useLiveViewActions`, which says so loudly.
 */
export function useOptionalLiveViewActions(): LiveViewActions | null {
  return useContext(LiveViewActionsContext);
}

export function useLiveViewActions(): LiveViewActions {
  const context = useContext(LiveViewActionsContext);
  if (!context) {
    throw new Error(
      'useLiveViewActions must be used within a LiveViewActionsProvider'
    );
  }
  return context;
}
