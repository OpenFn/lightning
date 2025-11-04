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
  navigate: (path: string) => void;
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

export function useLiveViewActions(): LiveViewActions {
  const context = useContext(LiveViewActionsContext);
  if (!context) {
    throw new Error(
      'useLiveViewActions must be used within a LiveViewActionsProvider'
    );
  }
  return context;
}
