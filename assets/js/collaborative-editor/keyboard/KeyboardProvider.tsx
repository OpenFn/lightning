/**
 * Priority-based keyboard shortcut system using tinykeys
 *
 * This module provides a centralized keyboard handling system where multiple
 * components can register handlers for the same key combination with explicit
 * priorities. The system ensures the highest priority handler executes, with
 * a fallback mechanism if a handler returns false.
 *
 * Features:
 * - Explicit priority-based handler selection
 * - Automatic preventDefault and stopPropagation (configurable)
 * - Always works in form fields (no configuration needed)
 * - Efficient: only one tinykeys listener per key combo
 * - Return false to pass to next handler
 * - Enable/disable handlers without unmounting
 *
 * Usage:
 * ```tsx
 * <KeyboardProvider>
 *   <YourApp />
 * </KeyboardProvider>
 *
 * // In component:
 * useKeyboardShortcut("Escape", () => {
 *   console.log("Escape pressed");
 * }, 10); // Priority number
 * ```
 */

import {
  createContext,
  useContext,
  useRef,
  useEffect,
  useCallback,
  useMemo,
  type ReactNode,
} from 'react';
import { tinykeys } from 'tinykeys';

import type {
  Handler,
  KeyboardContextValue,
  KeyboardHandlerOptions,
  KeyboardHandlerCallback,
} from './types';

const KeyboardContext = createContext<KeyboardContextValue | null>(null);

export interface KeyboardProviderProps {
  children: ReactNode;
}

export function KeyboardProvider({ children }: KeyboardProviderProps) {
  // Registry maps key combos to handler arrays
  const registry = useRef(new Map<string, Handler[]>());

  // Unsubscribers for tinykeys listeners
  const unsubscribers = useRef(new Map<string, () => void>());

  /**
   * Register a keyboard handler
   */
  const register = useCallback(
    (
      combos: string,
      handler: Omit<Handler, 'id' | 'registeredAt' | 'options'> & {
        options?: KeyboardHandlerOptions;
      }
    ): (() => void) => {
      // Create full handler with defaults
      const fullHandler: Handler = {
        ...handler,
        id: Math.random().toString(36).substring(7),
        registeredAt: Date.now(),
        options: {
          preventDefault: handler.options?.preventDefault ?? true,
          stopPropagation: handler.options?.stopPropagation ?? true,
          enabled: handler.options?.enabled ?? true,
        },
      };

      // Split combo string into individual combos
      const comboList = combos.split(',').map(c => c.trim());

      comboList.forEach(combo => {
        const existing = registry.current.get(combo) || [];
        registry.current.set(combo, [...existing, fullHandler]);

        // Only bind tinykeys if this is the first handler for this combo
        if (existing.length === 0) {
          const unsubscribe = tinykeys(window, {
            [combo]: (event: KeyboardEvent) => {
              const handlers = registry.current.get(combo);
              if (!handlers || handlers.length === 0) return;

              // Sort by priority (desc), then by registeredAt (desc)
              const sorted = [...handlers]
                .filter(h => h.options.enabled) // Only enabled handlers
                .sort((a, b) => {
                  if (b.priority !== a.priority) {
                    return b.priority - a.priority;
                  }
                  return b.registeredAt - a.registeredAt;
                });

              // Try handlers in priority order
              for (const handler of sorted) {
                try {
                  const result = handler.callback(event);

                  // If handler didn't return false, it claimed the event
                  if (result !== false) {
                    if (handler.options.preventDefault) {
                      event.preventDefault();
                    }
                    if (handler.options.stopPropagation) {
                      event.stopPropagation();
                    }
                    break; // Stop trying handlers
                  }
                  // result === false: try next handler
                } catch (error: unknown) {
                  console.error(
                    `[KeyboardProvider] Error in handler for "${combo}":`,
                    error
                  );
                  // Continue to next handler on error
                }
              }
            },
          });

          unsubscribers.current.set(combo, unsubscribe);
        }
      });

      // Return cleanup function
      return () => {
        comboList.forEach(combo => {
          const current = registry.current.get(combo) || [];
          const filtered = current.filter(h => h.id !== fullHandler.id);

          if (filtered.length === 0) {
            // Last handler for this combo - unbind tinykeys
            registry.current.delete(combo);
            const unsubscribe = unsubscribers.current.get(combo);
            unsubscribe?.();
            unsubscribers.current.delete(combo);
          } else {
            // Still handlers left, just update registry
            registry.current.set(combo, filtered);
          }
        });
      };
    },
    []
  );

  // Cleanup all on unmount
  useEffect(() => {
    const unsubs = unsubscribers.current;
    const reg = registry.current;
    return () => {
      unsubs.forEach(unsubscribe => unsubscribe());
      unsubs.clear();
      reg.clear();
    };
  }, []);

  return (
    <KeyboardContext.Provider value={{ register }}>
      {children}
    </KeyboardContext.Provider>
  );
}

/**
 * Hook to register keyboard shortcuts
 *
 * @param combos - Comma-separated key combinations
 * (e.g., "Escape", "Cmd+Enter, Ctrl+Enter")
 * @param callback - Handler function (return false to pass to next handler)
 * @param priority - Handler priority (higher = executes first)
 * @param options - Additional configuration
 *
 * @example
 * ```tsx
 * // Basic usage
 * useKeyboardShortcut("Escape", () => {
 *   closeModal();
 * }, 100); // High priority
 *
 * // With options
 * useKeyboardShortcut("Enter", () => {
 *   submitForm();
 * }, 0, { // Default priority
 *   preventDefault: false, // Don't prevent default
 * });
 *
 * // Return false to pass to next handler
 * useKeyboardShortcut("Escape", (e) => {
 *   if (monacoHasFocus) {
 *     monacoRef.current.blur();
 *     return false; // Let next handler run
 *   }
 *   closeEditor();
 * }, 50); // IDE priority
 * ```
 */
export function useKeyboardShortcut(
  combos: string,
  callback: KeyboardHandlerCallback,
  priority: number = 0,
  options?: KeyboardHandlerOptions
) {
  const context = useContext(KeyboardContext);

  if (!context) {
    throw new Error('useKeyboardShortcut must be used within KeyboardProvider');
  }

  const { register } = context;

  // Stable callback ref to avoid re-registering on every render
  const callbackRef = useRef(callback);
  useEffect(() => {
    callbackRef.current = callback;
  }, [callback]);

  // Stable options ref
  const optionsRef = useRef(options);
  useEffect(() => {
    optionsRef.current = options;
  }, [options]);

  // Serialize options for shallow comparison
  const serializedOptions = useMemo(() => JSON.stringify(options), [options]);

  useEffect(() => {
    return register(
      combos,
      optionsRef.current === undefined
        ? {
            callback: event => callbackRef.current(event),
            priority,
          }
        : {
            callback: event => callbackRef.current(event),
            priority,
            options: optionsRef.current,
          }
    );
  }, [combos, priority, serializedOptions, register]);
}
