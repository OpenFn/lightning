/**
 * MonacoRefContext
 *
 * Provides shared access to Monaco editor ref and diff dismissal callbacks.
 * This allows AIAssistantPanelWrapper to trigger diff mode in the Monaco editor
 * rendered by FullScreenIDE without prop drilling.
 *
 * Usage:
 * - CollaborativeEditor creates context via MonacoRefProvider
 * - AIAssistantPanelWrapper registers dismissal callback via useRegisterDiffDismissalCallback
 * - CollaborativeMonaco calls registered callbacks when user dismisses diff
 * - Enables job code preview feature (Phase 3 of Monaco diff preview plan)
 */

import type React from 'react';
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  type RefObject,
} from 'react';

import type { MonacoHandle } from '../components/CollaborativeMonaco';

export interface MonacoRefContextValue {
  monacoRef: RefObject<MonacoHandle> | null;
  registerDiffDismissalCallback: (callback: () => void) => () => void;
  handleDiffDismissed: () => void;
}

export const MonacoRefContext = createContext<MonacoRefContextValue | null>(
  null
);

interface MonacoRefProviderProps {
  children: React.ReactNode;
  monacoRef: RefObject<MonacoHandle>;
}

/**
 * Provider component that shares Monaco editor ref and manages diff dismissal callbacks.
 * Owns the callback registration system, ensuring clear ownership and lifecycle management.
 */
export function MonacoRefProvider({
  children,
  monacoRef,
}: MonacoRefProviderProps) {
  // Store callbacks in a ref to avoid re-renders when callbacks change
  const callbacksRef = useRef<Set<() => void>>(new Set());

  /**
   * Registers a callback to be invoked when the diff is dismissed.
   * Returns a cleanup function to unregister the callback.
   */
  const registerDiffDismissalCallback = useCallback((callback: () => void) => {
    callbacksRef.current.add(callback);
    return () => callbacksRef.current.delete(callback);
  }, []);

  /**
   * Invokes all registered diff dismissal callbacks.
   * Called by CollaborativeMonaco when user dismisses the diff.
   */
  const handleDiffDismissed = useCallback(() => {
    callbacksRef.current.forEach(callback => callback());
  }, []);

  return (
    <MonacoRefContext.Provider
      value={{ monacoRef, registerDiffDismissalCallback, handleDiffDismissed }}
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
 * Hook to access handleDiffDismissed callback from context.
 * Use this in CollaborativeMonaco to notify when the diff is dismissed.
 *
 * @returns handleDiffDismissed callback or undefined if outside provider
 */
export function useHandleDiffDismissed(): (() => void) | undefined {
  const context = useContext(MonacoRefContext);
  return context?.handleDiffDismissed;
}

/**
 * Hook to register a callback that will be invoked when the diff is dismissed.
 * Automatically handles cleanup when the component unmounts.
 *
 * Usage in AIAssistantPanelWrapper:
 * ```tsx
 * useRegisterDiffDismissalCallback(() => {
 *   setPreviewingMessageId(null);
 * });
 * ```
 *
 * @param callback - Function to call when diff is dismissed
 */
export function useRegisterDiffDismissalCallback(callback: () => void): void {
  const context = useContext(MonacoRefContext);
  const callbackRef = useRef(callback);

  // Keep callback ref up to date
  useEffect(() => {
    callbackRef.current = callback;
  }, [callback]);

  // Register/unregister callback on mount/unmount
  useEffect(() => {
    if (!context?.registerDiffDismissalCallback) return;

    const stableCallback = () => callbackRef.current();
    const cleanup = context.registerDiffDismissalCallback(stableCallback);

    return cleanup;
  }, [context]);
}
