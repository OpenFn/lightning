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
 * Debug information about a registered handler
 */
export interface HandlerDebugInfo {
  id: string;
  priority: number;
  enabled: boolean;
  registeredAt: number;
  preventDefault: boolean;
  stopPropagation: boolean;
}

/**
 * Debug information about all registered handlers
 */
export interface KeyboardDebugInfo {
  /** Map of key combinations to their registered handlers */
  handlers: Map<string, HandlerDebugInfo[]>;
  /** Total number of unique key combinations registered */
  comboCount: number;
  /** Total number of handlers across all combos */
  handlerCount: number;
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

  /**
   * Get debug information about all registered handlers (for debugging only)
   * @returns Debug information including all registered handlers and stats
   */
  getDebugInfo: () => KeyboardDebugInfo;
}

// No constants - library is generic. Consuming applications can define
// their own.
