/**
 * Phoenix Channel Mock Factories
 *
 * Reusable factory functions for creating Phoenix channel mocks with various
 * response patterns. These factories consolidate channel mocking logic that was
 * previously duplicated across test files.
 *
 * Usage:
 *   const mockChannel = createMockPhoenixChannel();
 *   const push = createMockPushWithResponse("ok", { data: "value" });
 *   const provider = createMockPhoenixChannelProvider(mockChannel);
 */

import {
  createMockPhoenixChannel as baseCreateMockPhoenixChannel,
  createMockPhoenixChannelProvider as baseCreateMockPhoenixChannelProvider,
  type MockPhoenixChannel,
  type MockPhoenixChannelProvider,
  type MockPush,
} from "../mocks/phoenixChannel";

// Re-export types for convenience
export type { MockPhoenixChannel, MockPhoenixChannelProvider, MockPush };

/**
 * Creates a mock Phoenix channel with optional topic override
 *
 * This is a convenience wrapper around the base mock that can be extended
 * with custom push behavior in tests.
 *
 * @param topic - Optional channel topic (defaults to "test:channel")
 * @returns Configured mock Phoenix channel
 *
 * @example
 * const channel = createMockPhoenixChannel("workflow:123");
 * channel.push = createMockPushWithResponse("ok", { adaptors: [] });
 */
export function createMockPhoenixChannel(
  topic: string = "test:channel"
): MockPhoenixChannel {
  return baseCreateMockPhoenixChannel(topic);
}

/**
 * Creates a mock push response handler with customizable status and payload
 *
 * This factory simplifies the common pattern of mocking channel.push() with
 * specific responses for different status codes (ok, error, timeout).
 *
 * @param okStatus - The status to respond to ("ok", "error", or "timeout")
 * @param okPayload - The payload to return for the ok status
 * @param errorPayload - Optional error payload (defaults to { reason: "Error" })
 * @returns MockPush object that can be returned from channel.push()
 *
 * @example
 * // Create a successful response
 * const push = createMockPushWithResponse("ok", { adaptors: mockData });
 * mockChannel.push = () => push;
 *
 * @example
 * // Create an error response
 * const push = createMockPushWithResponse("error", undefined, {
 *   reason: "Not found"
 * });
 */
export function createMockPushWithResponse(
  okStatus: "ok" | "error" | "timeout",
  okPayload: unknown,
  errorPayload: unknown = { reason: "Error" }
): MockPush {
  const mockPush: MockPush = {
    receive(status: string, callback: (response?: unknown) => void) {
      if (status === "ok" && okStatus === "ok") {
        setTimeout(() => callback(okPayload), 0);
      } else if (status === "error" && okStatus === "error") {
        setTimeout(() => callback(errorPayload), 0);
      } else if (status === "timeout" && okStatus === "timeout") {
        setTimeout(() => callback(), 0);
      }
      return mockPush;
    },
  };
  return mockPush;
}

/**
 * Creates a mock push that handles all three status types (ok, error, timeout)
 *
 * This is useful for more complex scenarios where the test needs to handle
 * multiple status types in sequence.
 *
 * @param okPayload - Payload for "ok" status
 * @param errorPayload - Payload for "error" status (defaults to { reason: "Error" })
 * @returns MockPush object
 *
 * @example
 * mockChannel.push = () => createMockPushWithAllStatuses({ data: "success" });
 */
export function createMockPushWithAllStatuses(
  okPayload: unknown,
  errorPayload: unknown = { reason: "Error" }
): MockPush {
  const mockPush: MockPush = {
    receive(status: string, callback: (response?: unknown) => void) {
      if (status === "ok") {
        setTimeout(() => callback(okPayload), 0);
      } else if (status === "error") {
        setTimeout(() => callback(errorPayload), 0);
      } else if (status === "timeout") {
        setTimeout(() => callback(), 0);
      }
      return mockPush;
    },
  };
  return mockPush;
}

/**
 * Creates a mock channel provider wrapping the given channel
 *
 * This is a convenience wrapper for creating channel providers in tests.
 *
 * @param channel - Optional channel to wrap (defaults to new mock channel)
 * @returns Mock channel provider
 *
 * @example
 * const channel = createMockPhoenixChannel();
 * const provider = createMockPhoenixChannelProvider(channel);
 * store._connectChannel(provider);
 */
export function createMockPhoenixChannelProvider(
  channel: MockPhoenixChannel | null = null
): MockPhoenixChannelProvider {
  return baseCreateMockPhoenixChannelProvider(channel);
}

/**
 * Configures a mock channel to respond with specific payloads for named events
 *
 * This factory simplifies setting up channel.push() with event-specific responses,
 * which is a common pattern in store tests.
 *
 * @param channel - The mock channel to configure
 * @param eventResponses - Map of event names to response payloads
 *
 * @example
 * const channel = createMockPhoenixChannel();
 * configureMockChannelPush(channel, {
 *   "request_adaptors": { adaptors: mockAdaptorsList },
 *   "get_context": { user: mockUser, project: mockProject }
 * });
 */
export function configureMockChannelPush(
  channel: MockPhoenixChannel,
  eventResponses: Record<string, unknown>
): void {
  channel.push = (event: string, _payload: unknown) => {
    const responsePayload = eventResponses[event];

    if (responsePayload) {
      return createMockPushWithAllStatuses(responsePayload);
    }

    // Default response if event not found
    return createMockPushWithAllStatuses({ status: "ok" });
  };
}

/**
 * Creates a mock channel with pre-configured event responses
 *
 * Convenience function that creates a channel and configures its push behavior
 * in one step.
 *
 * @param eventResponses - Map of event names to response payloads
 * @param topic - Optional channel topic
 * @returns Configured mock channel
 *
 * @example
 * const channel = createMockChannelWithResponses({
 *   "request_adaptors": { adaptors: [] },
 *   "get_context": { user: null, project: null }
 * });
 */
export function createMockChannelWithResponses(
  eventResponses: Record<string, unknown>,
  topic: string = "test:channel"
): MockPhoenixChannel {
  const channel = createMockPhoenixChannel(topic);
  configureMockChannelPush(channel, eventResponses);
  return channel;
}

/**
 * Creates a mock channel that always returns errors
 *
 * Useful for testing error handling paths.
 *
 * @param errorReason - Error reason to return (defaults to "Server error")
 * @param topic - Optional channel topic
 * @returns Mock channel configured to return errors
 *
 * @example
 * const channel = createMockChannelWithError("Not authorized");
 * store._connectChannel(createMockPhoenixChannelProvider(channel));
 */
export function createMockChannelWithError(
  errorReason: string = "Server error",
  topic: string = "test:channel"
): MockPhoenixChannel {
  const channel = createMockPhoenixChannel(topic);
  channel.push = (_event: string, _payload: unknown) => {
    return createMockPushWithResponse("error", undefined, {
      reason: errorReason,
    });
  };
  return channel;
}

/**
 * Creates a mock channel that always times out
 *
 * Useful for testing timeout handling.
 *
 * @param topic - Optional channel topic
 * @returns Mock channel configured to timeout
 *
 * @example
 * const channel = createMockChannelWithTimeout();
 * store._connectChannel(createMockPhoenixChannelProvider(channel));
 */
export function createMockChannelWithTimeout(
  topic: string = "test:channel"
): MockPhoenixChannel {
  const channel = createMockPhoenixChannel(topic);
  channel.push = (_event: string, _payload: unknown) => {
    return createMockPushWithResponse("timeout", undefined);
  };
  return channel;
}
