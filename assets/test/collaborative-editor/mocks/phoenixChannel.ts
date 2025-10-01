/**
 * Mock Phoenix Channel for testing collaborative editor functionality
 *
 * Provides a reusable mock implementation of Phoenix Channel that can be used
 * across different test files for consistent testing of channel-dependent features.
 */

import { type Channel } from "phoenix";

export interface MockPhoenixChannel extends Channel {
  on: (event: string, handler: (message: unknown) => void) => void;
  off: (event: string, handler: (message: unknown) => void) => void;
  push: (event: string, payload: unknown, timeout?: number) => MockPush;
  join: (timeout?: number) => MockPush;
  leave: (timeout?: number) => MockPush;
  onClose: (callback: () => void) => void;
  onError: (callback: (error: unknown) => void) => void;
  state: "closed" | "errored" | "joined" | "joining" | "leaving";
  topic: string;
  joinPush: MockPush;
  socket: unknown;
}

export interface MockPush {
  receive: (status: string, callback: (response?: unknown) => void) => MockPush;
}

export interface MockPhoenixChannelProvider {
  channel: MockPhoenixChannel | null;
}

/**
 * Creates a mock Phoenix channel for testing
 */
export function createMockPhoenixChannel(
  topic: string = "test:channel"
): MockPhoenixChannel {
  const eventHandlers = new Map<string, Set<(message: unknown) => void>>();
  let channelState: MockPhoenixChannel["state"] = "closed";
  const closeCallbacks: (() => void)[] = [];
  const errorCallbacks: ((error: unknown) => void)[] = [];

  const createMockPush = (): MockPush => ({
    receive(status: string, callback: (response?: unknown) => void) {
      setTimeout(() => {
        if (status === "ok") {
          callback({ status: "ok" });
        } else if (status === "error") {
          callback({ error: "Mock error" });
        }
      }, 0);
      return this;
    },
  });

  const mockChannel: MockPhoenixChannel = {
    state: channelState,
    topic,
    socket: null,
    joinPush: createMockPush(),

    on(event: string, handler: (message: unknown) => void) {
      if (!eventHandlers.has(event)) {
        eventHandlers.set(event, new Set());
      }
      eventHandlers.get(event)?.add(handler);
    },

    off(event: string, handler: (message: unknown) => void) {
      const handlers = eventHandlers.get(event);
      if (handlers) {
        handlers.delete(handler);
      }
    },

    push(_event: string, _payload: unknown, _timeout?: number): MockPush {
      return createMockPush();
    },

    join(_timeout?: number): MockPush {
      channelState = "joining";
      const joinPush = createMockPush();
      setTimeout(() => {
        channelState = "joined";
        mockChannel.state = channelState;
      }, 0);
      return joinPush;
    },

    leave(_timeout?: number): MockPush {
      channelState = "leaving";
      const leavePush = createMockPush();
      setTimeout(() => {
        channelState = "closed";
        mockChannel.state = channelState;
      }, 0);
      return leavePush;
    },

    onClose(callback: () => void) {
      closeCallbacks.push(callback);
    },

    onError(callback: (error: unknown) => void) {
      errorCallbacks.push(callback);
    },
  };

  // Add helper methods for testing
  const mockChannelWithHelpers = mockChannel as MockPhoenixChannel & {
    _test: {
      emit: (event: string, message: unknown) => void;
      triggerClose: () => void;
      triggerError: (error: unknown) => void;
      getHandlers: (
        event: string
      ) => Set<(message: unknown) => void> | undefined;
      setState: (state: MockPhoenixChannel["state"]) => void;
    };
  };

  mockChannelWithHelpers._test = {
    emit(event: string, message: unknown) {
      const handlers = eventHandlers.get(event);
      if (handlers) {
        handlers.forEach(handler => {
          try {
            handler(message);
          } catch (error) {
            console.error(`Error in mock channel handler for ${event}:`, error);
          }
        });
      }
    },

    triggerClose() {
      channelState = "closed";
      closeCallbacks.forEach(callback => callback());
    },

    triggerError(error: unknown) {
      channelState = "errored";
      errorCallbacks.forEach(callback => callback(error));
    },

    getHandlers(event: string) {
      return eventHandlers.get(event);
    },

    setState(state: MockPhoenixChannel["state"]) {
      channelState = state;
      mockChannel.state = state;
    },
  };

  return mockChannelWithHelpers;
}

/**
 * Creates a mock Phoenix channel provider for testing
 */
export function createMockPhoenixChannelProvider(
  channel: MockPhoenixChannel | null = null
): MockPhoenixChannelProvider {
  return {
    channel: channel || createMockPhoenixChannel(),
  };
}

/**
 * Test helper to wait for async operations to complete
 */
export function waitForAsync(ms: number = 0): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Waits for a condition to become true by polling at regular intervals
 * This is a testing-library/react waitFor alternative for non-React contexts
 *
 * @param condition - Function that returns true when the wait condition is met
 * @param options - Configuration options
 * @param options.timeout - Maximum time to wait in milliseconds (default: 1000)
 * @param options.interval - Time between condition checks in milliseconds (default: 50)
 * @throws Error if timeout is reached before condition becomes true
 *
 * @example
 * await waitForCondition(() => store.getSnapshot().isLoading === false);
 */
export async function waitForCondition(
  condition: () => boolean,
  options: { timeout?: number; interval?: number } = {}
): Promise<void> {
  const { timeout = 1000, interval = 50 } = options;
  const startTime = Date.now();

  while (!condition()) {
    if (Date.now() - startTime > timeout) {
      throw new Error(`waitForCondition timeout after ${timeout}ms`);
    }
    await waitForAsync(interval);
  }
}
