/**
 * Session Context Store Test Helpers
 *
 * Utility functions specifically for testing session context store functionality.
 * These helpers simplify common test patterns for session context requests,
 * channel event handling, and validation testing.
 *
 * Usage:
 *   const channel = configureMockChannelForContext(mockChannel, mockResponse);
 *   await testSessionContextRequest(store, expectedData);
 */

import type { SessionContextStore } from "../../../js/collaborative-editor/stores/createSessionContextStore";
import type {
  UserContext,
  ProjectContext,
  AppConfig,
  Permissions,
  WebhookAuthMethod,
} from "../../../js/collaborative-editor/types/sessionContext";

import {
  createMockPhoenixChannel,
  createMockPushWithAllStatuses,
  type MockPhoenixChannel,
} from "./channelMocks";

import { waitForAsync } from "../mocks/phoenixChannel";

// Re-export waitForAsync for convenience
export { waitForAsync };

/**
 * Configures a mock channel to respond to session context requests
 *
 * Sets up the channel's push method to handle "get_context" events with
 * the provided response data.
 *
 * @param channel - The mock channel to configure
 * @param response - The session context response data
 * @param responseStatus - Status to return ("ok", "error", or "timeout")
 *
 * @example
 * const channel = createMockPhoenixChannel();
 * configureMockChannelForContext(channel, {
 *   user: mockUser,
 *   project: mockProject,
 *   config: mockConfig
 * });
 */
export function configureMockChannelForContext(
  channel: MockPhoenixChannel,
  response: {
    user: UserContext | null;
    project: ProjectContext | null;
    config: AppConfig;
    permissions: Permissions;
    latest_snapshot_lock_version: number;
    webhook_auth_methods: WebhookAuthMethod[];
  },
  responseStatus: "ok" | "error" | "timeout" = "ok"
): void {
  channel.push = (event: string, _payload: unknown) => {
    if (event === "get_context") {
      if (responseStatus === "ok") {
        return createMockPushWithAllStatuses(response);
      } else if (responseStatus === "error") {
        return createMockPushWithAllStatuses(undefined, {
          reason: "Server error",
        });
      } else {
        // timeout
        return {
          receive(status: string, callback: (response?: unknown) => void) {
            if (status === "timeout") {
              setTimeout(() => callback(), 0);
            }
            return this;
          },
        };
      }
    }

    // Default response for other events
    return createMockPushWithAllStatuses({ status: "ok" });
  };
}

/**
 * Simulates a session_context event from the channel
 *
 * Triggers the channel's event handler as if the server pushed a
 * session_context event.
 *
 * @param channel - The mock channel
 * @param contextData - The session context data to emit
 *
 * @example
 * emitSessionContextEvent(mockChannel, {
 *   user: updatedUser,
 *   project: updatedProject,
 *   config: updatedConfig
 * });
 */
export function emitSessionContextEvent(
  channel: MockPhoenixChannel,
  contextData: {
    user: UserContext | null;
    project: ProjectContext | null;
    config: AppConfig;
    permissions: Permissions;
    latest_snapshot_lock_version: number;
    webhook_auth_methods: WebhookAuthMethod[];
  }
): void {
  const channelWithTest = channel as MockPhoenixChannel & {
    _test: { emit: (event: string, message: unknown) => void };
  };

  channelWithTest._test.emit("session_context", contextData);
}

/**
 * Simulates a session_context_updated event from the channel
 *
 * Triggers the channel's event handler as if the server pushed a
 * session_context_updated event.
 *
 * @param channel - The mock channel
 * @param contextData - The updated session context data to emit
 *
 * @example
 * emitSessionContextUpdatedEvent(mockChannel, {
 *   user: newUser,
 *   project: newProject,
 *   config: newConfig
 * });
 */
export function emitSessionContextUpdatedEvent(
  channel: MockPhoenixChannel,
  contextData: {
    user: UserContext | null;
    project: ProjectContext | null;
    config: AppConfig;
    permissions: Permissions;
    latest_snapshot_lock_version: number;
    webhook_auth_methods: WebhookAuthMethod[];
  }
): void {
  const channelWithTest = channel as MockPhoenixChannel & {
    _test: { emit: (event: string, message: unknown) => void };
  };

  channelWithTest._test.emit("session_context_updated", contextData);
}

/**
 * Tests a session context request with expected response validation
 *
 * Helper that performs a session context request and validates the response
 * matches expected values.
 *
 * @param store - The session context store
 * @param expected - Expected session context values
 * @returns Promise that resolves when request completes
 *
 * @example
 * await testSessionContextRequest(store, {
 *   user: mockUser,
 *   project: mockProject,
 *   config: mockConfig
 * });
 */
export async function testSessionContextRequest(
  store: SessionContextStore,
  expected: {
    user: UserContext | null;
    project: ProjectContext | null;
    config: AppConfig;
    permissions: Permissions;
    latest_snapshot_lock_version: number;
    webhook_auth_methods: WebhookAuthMethod[];
  }
): Promise<void> {
  await store.requestSessionContext();

  const state = store.getSnapshot();

  expect(state.user).toEqual(expected.user);
  expect(state.project).toEqual(expected.project);
  expect(state.config).toEqual(expected.config);
  expect(state.permissions).toEqual(expected.permissions);
  expect(state.latestSnapshotLockVersion).toEqual(
    expected.latest_snapshot_lock_version
  );
  expect(state.isLoading).toBe(false);
  expect(state.error).toBe(null);
}

/**
 * Tests error handling for session context requests
 *
 * Helper that verifies the store handles errors correctly when requests fail.
 *
 * @param store - The session context store
 * @param errorMessageFragment - Fragment of expected error message
 * @returns Promise that resolves when request completes
 *
 * @example
 * await testSessionContextError(store, "Failed to request");
 */
export async function testSessionContextError(
  store: SessionContextStore,
  errorMessageFragment: string
): Promise<void> {
  await store.requestSessionContext();

  const state = store.getSnapshot();

  expect(state.error).not.toBe(null);
  expect(state.error?.includes(errorMessageFragment)).toBe(true);
  expect(state.isLoading).toBe(false);
}

/**
 * Verifies that event handlers are properly registered on a channel
 *
 * Checks that the expected event handlers exist on the mock channel.
 *
 * @param channel - The mock channel
 * @param events - Array of event names to check
 * @returns True if all handlers are registered
 *
 * @example
 * const hasHandlers = verifyEventHandlersRegistered(mockChannel, [
 *   "session_context",
 *   "session_context_updated"
 * ]);
 * expect(hasHandlers).toBe(true);
 */
export function verifyEventHandlersRegistered(
  channel: MockPhoenixChannel,
  events: string[]
): boolean {
  const channelWithTest = channel as MockPhoenixChannel & {
    _test: { getHandlers: (event: string) => Set<unknown> | undefined };
  };

  return events.every(event => {
    const handlers = channelWithTest._test.getHandlers(event);
    return handlers && handlers.size > 0;
  });
}

/**
 * Verifies that event handlers are properly removed from a channel
 *
 * Checks that event handlers have been cleaned up after unsubscribe.
 *
 * @param channel - The mock channel
 * @param events - Array of event names to check
 * @returns True if all handlers are removed
 *
 * @example
 * cleanup();
 * const isClean = verifyEventHandlersRemoved(mockChannel, [
 *   "session_context",
 *   "session_context_updated"
 * ]);
 * expect(isClean).toBe(true);
 */
export function verifyEventHandlersRemoved(
  channel: MockPhoenixChannel,
  events: string[]
): boolean {
  const channelWithTest = channel as MockPhoenixChannel & {
    _test: { getHandlers: (event: string) => Set<unknown> | undefined };
  };

  return events.every(event => {
    const handlers = channelWithTest._test.getHandlers(event);
    return !handlers || handlers.size === 0;
  });
}

/**
 * Creates a test scenario for session context updates over time
 *
 * Simulates a sequence of context updates and verifies the store state
 * after each update.
 *
 * @param store - The session context store
 * @param channel - The mock channel
 * @param updates - Array of context updates to apply sequentially
 * @returns Promise that resolves when all updates are complete
 *
 * @example
 * await simulateContextUpdateSequence(store, channel, [
 *   { user: user1, project: project1, config: config1 },
 *   { user: user2, project: project2, config: config2 }
 * ]);
 */
export async function simulateContextUpdateSequence(
  store: SessionContextStore,
  channel: MockPhoenixChannel,
  updates: Array<{
    user: UserContext | null;
    project: ProjectContext | null;
    config: AppConfig;
    permissions: Permissions;
    latest_snapshot_lock_version: number;
    webhook_auth_methods: WebhookAuthMethod[];
  }>
): Promise<void> {
  for (const update of updates) {
    emitSessionContextUpdatedEvent(channel, update);
    await waitForAsync(10); // Allow event handlers to process

    const state = store.getSnapshot();
    expect(state.user).toEqual(update.user);
    expect(state.project).toEqual(update.project);
    expect(state.config).toEqual(update.config);
  }
}

/**
 * Tests timestamp updates for session context changes
 *
 * Verifies that lastUpdated timestamp is properly set and increases
 * with each update.
 *
 * @param store - The session context store
 * @returns The lastUpdated timestamp
 *
 * @example
 * await store.requestSessionContext();
 * const timestamp1 = verifyTimestampUpdated(store);
 *
 * await waitForAsync(10);
 * emitSessionContextUpdatedEvent(channel, newData);
 * const timestamp2 = verifyTimestampUpdated(store);
 *
 * expect(timestamp2).toBeGreaterThanOrEqual(timestamp1);
 */
export function verifyTimestampUpdated(store: SessionContextStore): number {
  const state = store.getSnapshot();
  expect(state.lastUpdated).not.toBe(null);
  expect(typeof state.lastUpdated).toBe("number");
  expect(state.lastUpdated! > 0).toBe(true);
  return state.lastUpdated!;
}

/**
 * Creates a mock channel pre-configured for common test scenarios
 *
 * Factory function that creates channels with typical configurations.
 *
 * @param scenario - The test scenario type
 * @param customData - Optional custom data for the scenario
 * @returns Configured mock channel
 *
 * @example
 * const channel = createMockChannelForScenario("authenticated", {
 *   user: customUser
 * });
 *
 * @example
 * const channel = createMockChannelForScenario("error");
 */
export function createMockChannelForScenario(
  scenario: "authenticated" | "unauthenticated" | "error" | "timeout",
  customData?: Partial<{
    user: UserContext | null;
    project: ProjectContext | null;
    config: AppConfig;
    permissions: Permissions;
    latest_snapshot_lock_version: number;
    webhook_auth_methods: WebhookAuthMethod[];
  }>
): MockPhoenixChannel {
  const channel = createMockPhoenixChannel();

  // Import fixtures
  const {
    mockUserContext,
    mockProjectContext,
    mockAppConfig,
    mockPermissions,
  } = require("../fixtures/sessionContextData");

  switch (scenario) {
    case "authenticated":
      configureMockChannelForContext(channel, {
        user: customData?.user ?? mockUserContext,
        project: customData?.project ?? mockProjectContext,
        config: customData?.config ?? mockAppConfig,
        permissions: customData?.permissions ?? mockPermissions,
        latest_snapshot_lock_version:
          customData?.latest_snapshot_lock_version ?? 1,
        webhook_auth_methods: customData?.webhook_auth_methods ?? [],
      });
      break;

    case "unauthenticated":
      configureMockChannelForContext(channel, {
        user: null,
        project: null,
        config: customData?.config ?? mockAppConfig,
        permissions: customData?.permissions ?? mockPermissions,
        latest_snapshot_lock_version:
          customData?.latest_snapshot_lock_version ?? 1,
        webhook_auth_methods: customData?.webhook_auth_methods ?? [],
      });
      break;

    case "error":
      configureMockChannelForContext(
        channel,
        {
          user: null,
          project: null,
          config: mockAppConfig,
          permissions: mockPermissions,
          latest_snapshot_lock_version: 1,
          webhook_auth_methods: [],
        },
        "error"
      );
      break;

    case "timeout":
      configureMockChannelForContext(
        channel,
        {
          user: null,
          project: null,
          config: mockAppConfig,
          permissions: mockPermissions,
          latest_snapshot_lock_version: 1,
          webhook_auth_methods: [],
        },
        "timeout"
      );
      break;
  }

  return channel;
}
