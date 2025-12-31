/**
 * MonacoRefContext
 *
 * Provides shared access to Monaco editor ref for diff preview functionality.
 * This allows AIAssistantPanelWrapper to trigger diff mode in the Monaco editor
 * rendered by FullScreenIDE without prop drilling.
 *
 * Usage:
 * - FullScreenIDE provides the monaco ref via MonacoRefProvider
 * - AIAssistantPanelWrapper consumes via useMonacoRef
 * - Enables job code preview feature (Phase 3 of Monaco diff preview plan)
 */

import type React from 'react';
import {
  createContext,
  useContext,
  type RefObject,
  type MutableRefObject,
} from 'react';

import type { MonacoHandle } from '../components/CollaborativeMonaco';

export interface MonacoRefContextValue {
  monacoRef: RefObject<MonacoHandle> | null;
  onDiffDismissed?: () => void;
  onDiffDismissedRef?: MutableRefObject<(() => void) | undefined>;
}

export const MonacoRefContext = createContext<MonacoRefContextValue | null>(
  null
);

interface MonacoRefProviderProps {
  children: React.ReactNode;
  monacoRef: RefObject<MonacoHandle>;
  onDiffDismissed?: () => void;
  onDiffDismissedRef?: MutableRefObject<(() => void) | undefined>;
}

/**
 * Provider component that shares Monaco editor ref with child components
 */
export function MonacoRefProvider({
  children,
  monacoRef,
  onDiffDismissed,
  onDiffDismissedRef,
}: MonacoRefProviderProps) {
  return (
    <MonacoRefContext.Provider
      value={{ monacoRef, onDiffDismissed, onDiffDismissedRef }}
    >
      {children}
    </MonacoRefContext.Provider>
  );
}

/**
 * Hook to access Monaco editor ref from context
 *
 * @returns Monaco editor ref or null if outside provider
 */
export function useMonacoRef(): RefObject<MonacoHandle> | null {
  const context = useContext(MonacoRefContext);
  return context?.monacoRef ?? null;
}

/**
 * Hook to access onDiffDismissed callback from context
 *
 * @returns onDiffDismissed callback or undefined if outside provider
 */
export function useOnDiffDismissed(): (() => void) | undefined {
  const context = useContext(MonacoRefContext);
  return context?.onDiffDismissed;
}
