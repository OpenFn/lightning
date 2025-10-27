/**
 * Phoenix Channel Mock Helpers
 *
 * These helpers use Phoenix terminology ("ok", "error", "timeout") to match
 * Phoenix Channel's `.receive("ok", ...)` pattern and ensure correct error structure:
 * { errors: { base: ["message"] }, type: "error_type" }
 *
 * Key principles:
 * - Be explicit: Developers should clearly see what channel behavior they're mocking
 * - Match Phoenix: Use ok/error/timeout to match Phoenix's internal terminology
 * - Correct by default: Ensures correct error structure automatically
 *
 * This matches the expected format in useChannel.ts channelRequest()
 */

import { vi } from 'vitest';
import type { Channel } from 'phoenix';
import type { MockPush } from '../mocks/phoenixChannel';

// Re-export base Phoenix Channel mocks
export {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  type MockPhoenixChannel,
  type MockPhoenixChannelProvider,
  type MockPush,
} from '../mocks/phoenixChannel';

/**
 * Phoenix Channel Error Structure
 * Matches the format expected by channelRequest in useChannel.ts
 */
export interface PhoenixChannelError {
  errors: Record<string, string[]>;
  type: string;
}

/**
 * Creates a properly structured Phoenix channel error response
 *
 * @param message - Error message (will be placed in errors.base[0])
 * @param type - Error type identifier (e.g., "save_error", "validation_error")
 * @returns Structured error object
 *
 * @example
 * createChannelError("Save failed", "save_error")
 * // Returns: { errors: { base: ["Save failed"] }, type: "save_error" }
 */
export function createChannelError(
  message: string,
  type: string = 'error'
): PhoenixChannelError {
  return {
    errors: { base: [message] },
    type,
  };
}

/**
 * Configuration for mock push responses
 */
export interface MockPushConfig {
  /** Response to send on "ok" status */
  okResponse?: unknown;
  /** Error to send on "error" status (will be converted to Phoenix format if string) */
  errorResponse?: string | PhoenixChannelError;
  /** Whether to call timeout handler */
  shouldTimeout?: boolean;
  /** Delay before calling handlers (defaults to 0) */
  delay?: number;
}

/**
 * Creates a mock push with flexible response configuration
 *
 * This is the core building block for channel mocks with proper error structure.
 *
 * @param config - Configuration for ok, error, and timeout responses
 * @returns MockPush object with chainable receive() method
 *
 * @example
 * // Ok response
 * const push = createMockPush({ okResponse: { saved_at: "..." } });
 *
 * @example
 * // Error response with structured error
 * const push = createMockPush({
 *   errorResponse: "Save failed",  // Automatically formatted
 * });
 *
 * @example
 * // Timeout response
 * const push = createMockPush({ shouldTimeout: true });
 */
export function createMockPush(config: MockPushConfig = {}): MockPush {
  const {
    okResponse,
    errorResponse,
    shouldTimeout = false,
    delay = 0,
  } = config;

  const mockPush: MockPush = {
    receive(status: string, callback: (response?: unknown) => void) {
      if (status === 'ok' && okResponse !== undefined) {
        setTimeout(() => callback(okResponse), delay);
      } else if (status === 'error' && errorResponse !== undefined) {
        setTimeout(() => {
          const error =
            typeof errorResponse === 'string'
              ? createChannelError(errorResponse, 'error')
              : errorResponse;
          callback(error);
        }, delay);
      } else if (status === 'timeout' && shouldTimeout) {
        setTimeout(() => callback(), delay);
      }
      return mockPush;
    },
  };

  return mockPush;
}

/**
 * Creates a mock channel.push function that returns "ok" responses
 *
 * Uses Phoenix's `.receive("ok", ...)` terminology to make it clear this mock
 * simulates a successful channel operation.
 *
 * Automatically wraps with vi.fn() for call tracking and verification.
 *
 * @param response - Response data to return on "ok" status
 * @returns Function suitable for mockChannel.push assignment
 *
 * @example
 * mockChannel.push = createMockChannelPushOk({ lock_version: 1 });
 *
 * @example
 * mockChannel.push = createMockChannelPushOk({ saved_at: "...", lock_version: 1 });
 */
export function createMockChannelPushOk(response: unknown): Channel['push'] {
  const pushFn = (_event: string, _payload: unknown) =>
    createMockPush({ okResponse: response });

  return vi.fn(pushFn) as unknown as Channel['push'];
}

/**
 * Creates a mock channel.push function that returns "error" responses
 *
 * Uses Phoenix's `.receive("error", ...)` terminology and automatically formats
 * errors in the structure expected by channelRequest.
 *
 * Automatically wraps with vi.fn() for call tracking and verification.
 *
 * @param message - Error message (will be placed in errors.base[0])
 * @param type - Error type identifier (defaults to "error")
 * @returns Function suitable for mockChannel.push assignment
 *
 * @example
 * mockChannel.push = createMockChannelPushError("Save failed", "save_error");
 *
 * @example
 * mockChannel.push = createMockChannelPushError("Database error", "db_error");
 */
export function createMockChannelPushError(
  message: string,
  type: string = 'error'
): Channel['push'] {
  const pushFn = (_event: string, _payload: unknown) =>
    createMockPush({ errorResponse: createChannelError(message, type) });

  return vi.fn(pushFn) as unknown as Channel['push'];
}

/**
 * Creates a mock channel.push function that triggers "timeout" handlers
 *
 * Uses Phoenix's `.receive("timeout", ...)` terminology to simulate
 * channel operations that don't respond in time.
 *
 * Automatically wraps with vi.fn() for call tracking and verification.
 *
 * @returns Function suitable for mockChannel.push assignment
 *
 * @example
 * mockChannel.push = createMockChannelPushTimeout();
 */
export function createMockChannelPushTimeout(): Channel['push'] {
  const pushFn = (_event: string, _payload: unknown) =>
    createMockPush({ shouldTimeout: true });

  return vi.fn(pushFn) as unknown as Channel['push'];
}

/**
 * Configuration for event-specific mock responses
 */
interface EventResponseConfig {
  /** Map of event names to ok responses or response objects with ok/error/timeout */
  events: Record<
    string,
    | unknown
    | {
        ok?: unknown;
        error?: string | PhoenixChannelError;
        timeout?: boolean;
      }
  >;
  /** Default response for unmatched events (sent on "ok" status) */
  defaultResponse?: unknown;
}

/**
 * Creates a mock channel.push function with event-specific responses
 *
 * Allows different events to return different responses. Each event can specify
 * ok, error, or timeout behavior, matching Phoenix's receive handler pattern.
 *
 * Automatically wraps with vi.fn() for call tracking and verification.
 *
 * @param config - Event response configuration
 * @returns Function suitable for mockChannel.push assignment
 *
 * @example
 * // Simple event-to-ok-response mapping
 * mockChannel.push = createMockChannelPushByEvent({
 *   events: {
 *     "save_workflow": { saved_at: "...", lock_version: 1 },
 *     "validate_workflow_name": { workflow: { name: "..." } }
 *   }
 * });
 *
 * @example
 * // Event with explicit ok response
 * mockChannel.push = createMockChannelPushByEvent({
 *   events: {
 *     "save_workflow": {
 *       ok: { saved_at: "...", lock_version: 1 }
 *     }
 *   }
 * });
 *
 * @example
 * // Event with error response
 * mockChannel.push = createMockChannelPushByEvent({
 *   events: {
 *     "save_workflow": {
 *       error: "Save failed"  // Auto-formatted to Phoenix error structure
 *     }
 *   }
 * });
 */
export function createMockChannelPushByEvent(
  config: EventResponseConfig
): Channel['push'] {
  const { events, defaultResponse } = config;

  const pushFn = (event: string, _payload: unknown) => {
    const eventConfig = events[event];

    if (!eventConfig) {
      return createMockPush({
        okResponse: defaultResponse ?? { status: 'ok' },
      });
    }

    // Handle simple response (just the data)
    if (
      typeof eventConfig !== 'object' ||
      !(
        'ok' in eventConfig ||
        'error' in eventConfig ||
        'timeout' in eventConfig
      )
    ) {
      return createMockPush({ okResponse: eventConfig });
    }

    // Handle complex response with ok/error/timeout
    const complexConfig = eventConfig as {
      ok?: unknown;
      error?: string | PhoenixChannelError;
      timeout?: boolean;
    };
    return createMockPush({
      okResponse: complexConfig.ok,
      errorResponse: complexConfig.error,
      shouldTimeout: complexConfig.timeout,
    });
  };

  return vi.fn(pushFn) as unknown as Channel['push'];
}

/**
 * Creates a mock channel.push function with custom logic based on event and payload
 *
 * Provides maximum flexibility for tests that need to generate responses dynamically.
 * Your handler function determines what to return on the "ok", "error", or "timeout"
 * receive handlers based on the event name and payload.
 *
 * Automatically wraps with vi.fn() for call tracking and verification.
 *
 * @param handler - Function that receives event and payload, returns mock push config
 * @returns Function suitable for mockChannel.push assignment
 *
 * @example
 * // Workflow name validation that appends " 1"
 * mockChannel.push = createMockChannelPushWithHandler((event, payload) => {
 *   if (event === "validate_workflow_name") {
 *     const { workflow } = payload as { workflow: { name: string } };
 *     return { okResponse: { workflow: { name: workflow.name + " 1" } } };
 *   }
 *   return { okResponse: { status: "ok" } };
 * });
 *
 * @example
 * // Different responses based on payload content
 * mockChannel.push = createMockChannelPushWithHandler((event, payload) => {
 *   if (event === "save_workflow") {
 *     const { workflow } = payload as { workflow: { name: string } };
 *     if (workflow.name === "") {
 *       return { errorResponse: "Name cannot be empty" };
 *     }
 *     return { okResponse: { lock_version: 1 } };
 *   }
 *   return { okResponse: { status: "ok" } };
 * });
 */
export function createMockChannelPushWithHandler(
  handler: (event: string, payload: unknown) => MockPushConfig
): Channel['push'] {
  const pushFn = (event: string, payload: unknown) => {
    const config = handler(event, payload);
    return createMockPush(config);
  };

  return vi.fn(pushFn) as unknown as Channel['push'];
}
