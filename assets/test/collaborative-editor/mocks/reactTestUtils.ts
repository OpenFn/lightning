/**
 * React testing utilities for Vitest tests
 *
 * Since this project doesn't use React Testing Library, we create minimal
 * utilities to test React hooks with Vitest framework.
 */

import type { DependencyList } from "react";

import type {
  Adaptor,
  AdaptorState,
} from "../../../js/collaborative-editor/types/adaptor";

/**
 * Mock implementation of useSyncExternalStore for testing
 */
export function mockUseSyncExternalStore<T>(
  _subscribe: (callback: () => void) => () => void,
  getSnapshot: () => T,
  _getServerSnapshot?: () => T
): T {
  // In testing, we just return the current snapshot
  // Real implementation would handle subscriptions
  return getSnapshot();
}

/**
 * Mock implementation of useMemo for testing
 */
export function mockUseMemo<T>(factory: () => T, _deps: DependencyList): T {
  // In testing, we just call the factory function
  // Real implementation would handle dependency changes
  return factory();
}

/**
 * Mock session context value creator
 */
export interface MockSessionContext {
  adaptorStore: {
    subscribe: (listener: () => void) => () => void;
    getSnapshot: () => AdaptorState;
    withSelector: <T>(selector: (state: AdaptorState) => T) => () => T;
    requestAdaptors: () => Promise<void>;
    setAdaptors: (adaptors: Adaptor[]) => void;
    clearError: () => void;
    findAdaptorByName: (name: string) => Adaptor | null;
  };
}

/**
 * Creates a mock session context for testing hooks
 */
export function createMockSessionContext(
  adaptorStore: MockSessionContext["adaptorStore"]
): MockSessionContext {
  return {
    adaptorStore,
  };
}

/**
 * Mock useSession hook for testing
 */
let mockSessionValue: MockSessionContext | null = null;

export function setMockSessionValue(value: MockSessionContext) {
  mockSessionValue = value;
}

export function getMockSessionValue(): MockSessionContext {
  if (!mockSessionValue) {
    throw new Error("useSession must be used within a SessionProvider");
  }
  return mockSessionValue;
}

/**
 * Test wrapper to simulate hook behavior without React
 * This allows us to test the logic inside hooks by calling the functions directly
 */
export class HookTester<T> {
  private subscriptions: Set<() => void> = new Set();
  private lastSnapshot: T | undefined;

  constructor(
    private subscribe: (callback: () => void) => () => void,
    private getSnapshot: () => T
  ) {}

  /**
   * Simulate calling the hook and getting initial value
   */
  getValue(): T {
    return this.getSnapshot();
  }

  /**
   * Simulate subscribing to changes
   */
  startWatching(callback: (value: T) => void): () => void {
    const unsubscribe = this.subscribe(() => {
      const newSnapshot = this.getSnapshot();
      if (newSnapshot !== this.lastSnapshot) {
        this.lastSnapshot = newSnapshot;
        callback(newSnapshot);
      }
    });

    // Get initial value
    this.lastSnapshot = this.getSnapshot();
    callback(this.lastSnapshot);

    return unsubscribe;
  }

  /**
   * Clean up subscriptions
   */
  cleanup(): void {
    this.subscriptions.clear();
  }
}

/**
 * Create a hook tester for easier testing of hook-like behavior
 */
export function createHookTester<T>(
  subscribe: (callback: () => void) => () => void,
  getSnapshot: () => T
): HookTester<T> {
  return new HookTester(subscribe, getSnapshot);
}
