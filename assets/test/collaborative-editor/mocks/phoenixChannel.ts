/**
 * Mock Phoenix Channel for testing collaborative editor functionality
 *
 * Provides a reusable mock implementation of Phoenix Channel that can be used
 * across different test files for consistent testing of channel-dependent features.
 */

export interface MockPhoenixChannel {
  on: (event: string, handler: (message: unknown) => void) => void;
  off: (event: string, handler: (message: unknown) => void) => void;
  push: (event: string, payload: unknown, timeout?: number) => MockPush;
  join: (timeout?: number) => MockPush;
  leave: (timeout?: number) => MockPush;
  onClose: (callback: () => void) => void;
  onError: (callback: (error: unknown) => void) => void;
  state: "closed" | "errored" | "joined" | "joining" | "leaving";
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
export function createMockPhoenixChannel(): MockPhoenixChannel {
  const eventHandlers = new Map<string, Set<(message: unknown) => void>>();
  let channelState: MockPhoenixChannel["state"] = "closed";
  const closeCallbacks: (() => void)[] = [];
  const errorCallbacks: ((error: unknown) => void)[] = [];

  const mockChannel: MockPhoenixChannel = {
    state: channelState,

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

    push(event: string, _payload: unknown, _timeout?: number): MockPush {
      const mockPush: MockPush = {
        receive(status: string, callback: (response?: unknown) => void) {
          // Simulate async response
          setTimeout(() => {
            if (status === "ok") {
              // Simulate successful response based on event type
              if (event === "request_adaptors") {
                callback({ adaptors: [] });
              } else {
                callback({ status: "ok" });
              }
            } else if (status === "error") {
              callback({ error: "Mock error" });
            }
          }, 0);
          return mockPush;
        },
      };
      return mockPush;
    },

    join(_timeout?: number): MockPush {
      channelState = "joining";
      const mockPush: MockPush = {
        receive(status: string, callback: (response?: unknown) => void) {
          setTimeout(() => {
            if (status === "ok") {
              channelState = "joined";
              callback({ status: "joined" });
            }
          }, 0);
          return mockPush;
        },
      };
      return mockPush;
    },

    leave(_timeout?: number): MockPush {
      channelState = "leaving";
      const mockPush: MockPush = {
        receive(status: string, callback: (response?: unknown) => void) {
          setTimeout(() => {
            if (status === "ok") {
              channelState = "closed";
              callback({ status: "left" });
            }
          }, 0);
          return mockPush;
        },
      };
      return mockPush;
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
