/**
 * Redux DevTools Integration for useSyncExternalStore + Immer Stores
 *
 * This module provides a wrapper function that adds Redux DevTools support
 * to any store following our useSyncExternalStore + Immer pattern.
 *
 * Features:
 * - Automatic action tracking
 * - State snapshots sent to DevTools
 * - Time-travel debugging support
 * - Selective state serialization (exclude non-serializable objects)
 * - Conditional activation based on ENABLE_DEVTOOLS flag
 *
 * Usage:
 * ```typescript
 * const store = createMyStore();
 *
 * const devtools = wrapStoreWithDevTools(store, {
 *   name: 'MyStore',
 *   excludeKeys: ['ydoc', 'provider'], // Don't send these to DevTools
 * });
 *
 * // Use devtools.notify() instead of store notify()
 * // Call devtools.connect() after store initialization
 * ```
 */

/**
 * Minimal Redux DevTools types for our usage.
 * Based on @redux-devtools/extension but avoiding full import.
 */

/** Config options passed to DevTools.connect() */
interface ReduxDevToolsConfig {
  name: string;
  maxAge?: number;
  trace?: boolean;
  features?: {
    pause?: boolean;
    lock?: boolean;
    persist?: boolean;
    export?: boolean;
    import?: 'custom' | boolean;
    jump?: boolean;
    skip?: boolean;
    reorder?: boolean;
    dispatch?: boolean;
    test?: boolean;
  };
}

/** Message from DevTools extension */
interface DevToolsMessage {
  type: string;
  state?: string;
  payload?: any;
}

/** DevTools connection instance */
interface DevToolsConnection {
  send: (action: { type: string; timestamp?: number }, state: any) => void;
  subscribe: (listener: (message: DevToolsMessage) => void) => void;
  unsubscribe: () => void;
}

/** Redux DevTools Extension global */
interface ReduxDevtoolsExtension {
  connect: (config: ReduxDevToolsConfig) => DevToolsConnection;
}

/** Configuration for our wrapper */
interface DevToolsConfig {
  /**
   * Store name displayed in Redux DevTools
   */
  name: string;

  /**
   * State keys to exclude from DevTools (e.g., Y.Doc, large objects)
   */
  excludeKeys?: string[];

  /**
   * Maximum number of actions to keep in history
   */
  maxAge?: number;

  /**
   * Enable action stack traces for debugging
   */
  trace?: boolean;
}

interface DevToolsWrapper {
  /**
   * Initialize DevTools connection
   * Should be called after store is created
   */
  connect: () => void;

  /**
   * Disconnect DevTools
   * Should be called on cleanup
   */
  disconnect: () => void;

  /**
   * Send an action and current state to DevTools
   * Call this instead of the original notify()
   *
   * @param actionName - Human-readable action name (e.g., "selectJob")
   * @param getState - Function that returns current state
   */
  notifyWithAction: (actionName: string, getState: () => any) => void;

  /**
   * Get the original notify function (for stores that need it)
   */
  getOriginalNotify: () => (() => void) | null;
}

/**
 * Serialize state for DevTools, excluding specified keys
 */
function serializeState<T extends Record<string, any>>(
  state: T,
  excludeKeys: string[] = []
): Partial<T> {
  const serialized: any = {};

  for (const [key, value] of Object.entries(state)) {
    // Skip excluded keys
    if (excludeKeys.includes(key)) {
      continue;
    }

    // Handle special cases
    if (value === null || value === undefined) {
      serialized[key] = value;
    } else if (typeof value === 'function') {
      // Skip functions
      continue;
    } else if (value instanceof Map) {
      // Convert Map to object
      serialized[key] = Object.fromEntries(value);
    } else if (value instanceof Set) {
      // Convert Set to array
      serialized[key] = Array.from(value);
    } else {
      // Include primitive, array, or plain object
      serialized[key] = value;
    }
  }

  return serialized;
}

/**
 * Wrap a useSyncExternalStore + Immer store with Redux DevTools integration
 */
export function wrapStoreWithDevTools<TState extends Record<string, any>>(
  config: DevToolsConfig
): DevToolsWrapper {
  // Check if DevTools should be enabled
  if (!ENABLE_DEVTOOLS) {
    // Return no-op wrapper in production
    return {
      connect: () => {},
      disconnect: () => {},
      notifyWithAction: () => {},
      getOriginalNotify: () => null,
    };
  }

  // Check if Redux DevTools extension is available
  const devToolsExtension = (window as any).__REDUX_DEVTOOLS_EXTENSION__ as
    | ReduxDevtoolsExtension
    | undefined;

  if (!devToolsExtension) {
    console.warn(
      `[${config.name}] Redux DevTools extension not found. ` +
        'Install it from https://github.com/reduxjs/redux-devtools'
    );
    return {
      connect: () => {},
      disconnect: () => {},
      notifyWithAction: () => {},
      getOriginalNotify: () => null,
    };
  }

  let devTools: DevToolsConnection | null = null;
  let isTimeTravel = false;
  const originalNotify: (() => void) | null = null;

  const connect = () => {
    // Disconnect existing connection if any (handles hot reload)
    if (devTools) {
      devTools.unsubscribe();
      devTools = null;
    }

    devTools = devToolsExtension.connect({
      name: config.name,
      maxAge: config.maxAge ?? 50,
      trace: config.trace ?? false,
      features: {
        pause: true,
        lock: true,
        persist: false,
        export: true,
        import: 'custom',
        jump: true,
        skip: true,
        reorder: true,
        dispatch: true,
        test: false,
      },
    });

    if (!devTools) {
      console.warn(`[${config.name}] Failed to connect to Redux DevTools`);
      return;
    }

    // Initialize with empty state to register store in DevTools dropdown
    devTools.send({ type: `@@INIT` }, {});

    // Subscribe to DevTools actions (time-travel, reset, etc.)
    devTools.subscribe((message: any) => {
      if (message.type === 'DISPATCH' && message.state) {
        // Time-travel: DevTools is asking us to load a previous state
        try {
          isTimeTravel = true;

          // Parse the state (validates JSON but doesn't use it yet)
          // Store implementations will need to handle time-travel in Phase 3
          JSON.parse(message.state);

          // Log for debugging
          console.debug(
            `[${config.name}] Time-travel requested:`,
            message.payload,
            '(not fully implemented yet)'
          );

          // The store will need to handle this - we'll provide a callback
          // for now, just log it
        } catch (error) {
          console.error(
            `[${config.name}] Failed to parse DevTools state:`,
            error
          );
        } finally {
          isTimeTravel = false;
        }
      } else if (message.type === 'ACTION' && message.payload) {
        // Custom action dispatched from DevTools
        console.debug(
          `[${config.name}] Custom action from DevTools:`,
          message.payload
        );
      }
    });

    console.debug(`[${config.name}] Connected to Redux DevTools`);
  };

  const disconnect = () => {
    if (devTools) {
      devTools.unsubscribe();
      devTools = null;
    }
  };

  const notifyWithAction = (actionName: string, getState: () => TState) => {
    if (!devTools) {
      // DevTools not connected, do nothing
      return;
    }

    // Don't send actions during time-travel to prevent loops
    if (isTimeTravel) {
      return;
    }

    try {
      const state = getState();
      const serializedState = serializeState(state, config.excludeKeys);

      // Send action with state to DevTools
      devTools.send(
        {
          type: `${config.name}/${actionName}`,
          timestamp: Date.now(),
        },
        serializedState
      );
    } catch (error) {
      console.error(
        `[${config.name}] Failed to send action to DevTools:`,
        actionName,
        error
      );
    }
  };

  return {
    connect,
    disconnect,
    notifyWithAction,
    getOriginalNotify: () => originalNotify,
  };
}

/**
 * Helper to create action name from method name
 */
export function createActionName(methodName: string): string {
  return methodName;
}
