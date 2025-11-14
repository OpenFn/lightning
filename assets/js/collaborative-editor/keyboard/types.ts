/**
 * Type definitions for priority-based keyboard shortcut system
 */

/**
 * Handler options for configuring behavior
 */
export interface KeyboardHandlerOptions {
  /**
   * Prevent default browser behavior
   * @default true
   */
  preventDefault?: boolean;

  /**
   * Stop event propagation after handler executes
   * @default true
   */
  stopPropagation?: boolean;

  /**
   * Enable/disable handler without unmounting
   * @default true
   */
  enabled?: boolean;
}

/**
 * Handler callback function
 * Return false to pass event to next handler in priority order
 * Return void/true to claim the event and stop propagation
 */
export type KeyboardHandlerCallback = (event: KeyboardEvent) => boolean | void;

/**
 * Internal handler representation
 */
export interface Handler {
  id: string;
  callback: KeyboardHandlerCallback;
  priority: number;
  registeredAt: number;
  options: Required<KeyboardHandlerOptions>;
}

/**
 * Context value exposed by KeyboardProvider
 */
export interface KeyboardContextValue {
  /**
   * Register a keyboard handler
   * @param combos - Comma-separated key combinations
   *   (e.g., "Escape", "Cmd+Enter, Ctrl+Enter")
   * @param handler - Handler configuration
   * @returns Cleanup function to unregister the handler
   */
  register: (
    combos: string,
    handler: Omit<Handler, 'id' | 'registeredAt' | 'options'> & {
      options?: KeyboardHandlerOptions;
    }
  ) => () => void;
}

// No constants - library is generic. Consuming applications can define
// their own.
