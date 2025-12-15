/**
 * Tests for createSessionContextStore - Limits Handling
 *
 * This test suite covers:
 * - Handling of workflow_activation and github_sync limits
 * - get_limits message handling for multiple action types
 * - Proper state updates when limits are received
 */

import { describe, expect, test, vi } from 'vitest';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  waitForCondition,
  type MockPhoenixChannel,
} from '../mocks/phoenixChannel';

describe('createSessionContextStore - Limits Handling', () => {
  describe('get_limits response handling', () => {
    test('handles workflow_activation limit response', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      // Connect to channel
      const cleanup = store._connectChannel(mockProvider);

      // Simulate get_limits response for workflow_activation
      const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
        _test: { emit: (event: string, message: unknown) => void };
      };

      mockChannelWithTest._test.emit('get_limits', {
        action_type: 'activate_workflow',
        limit: { allowed: true, message: null },
      });

      // Wait for the event to be processed
      await waitForCondition(
        () => store.getSnapshot().limits.workflow_activation !== undefined
      );

      const state = store.getSnapshot();
      expect(state.limits.workflow_activation).toEqual({
        allowed: true,
        message: null,
      });

      cleanup();
    });

    test('handles workflow_activation limit exceeded', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      const cleanup = store._connectChannel(mockProvider);

      const errorMsg = 'Workflow activation limit exceeded';
      const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
        _test: { emit: (event: string, message: unknown) => void };
      };

      mockChannelWithTest._test.emit('get_limits', {
        action_type: 'activate_workflow',
        limit: { allowed: false, message: errorMsg },
      });

      await waitForCondition(
        () => store.getSnapshot().limits.workflow_activation !== undefined
      );

      const state = store.getSnapshot();
      expect(state.limits.workflow_activation).toEqual({
        allowed: false,
        message: errorMsg,
      });

      cleanup();
    });

    test('handles github_sync limit response', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      const cleanup = store._connectChannel(mockProvider);

      const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
        _test: { emit: (event: string, message: unknown) => void };
      };

      mockChannelWithTest._test.emit('get_limits', {
        action_type: 'github_sync',
        limit: { allowed: true, message: null },
      });

      await waitForCondition(
        () => store.getSnapshot().limits.github_sync !== undefined
      );

      const state = store.getSnapshot();
      expect(state.limits.github_sync).toEqual({
        allowed: true,
        message: null,
      });

      cleanup();
    });

    test('handles github_sync limit exceeded', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      const cleanup = store._connectChannel(mockProvider);

      const errorMsg = 'GitHub sync limit exceeded';
      const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
        _test: { emit: (event: string, message: unknown) => void };
      };

      mockChannelWithTest._test.emit('get_limits', {
        action_type: 'github_sync',
        limit: { allowed: false, message: errorMsg },
      });

      await waitForCondition(
        () => store.getSnapshot().limits.github_sync !== undefined
      );

      const state = store.getSnapshot();
      expect(state.limits.github_sync).toEqual({
        allowed: false,
        message: errorMsg,
      });

      cleanup();
    });

    test('handles multiple limit types independently', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      const cleanup = store._connectChannel(mockProvider);

      const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
        _test: { emit: (event: string, message: unknown) => void };
      };

      // Send different limits
      mockChannelWithTest._test.emit('get_limits', {
        action_type: 'new_run',
        limit: { allowed: true, message: null },
      });

      mockChannelWithTest._test.emit('get_limits', {
        action_type: 'activate_workflow',
        limit: { allowed: false, message: 'Workflow limit reached' },
      });

      mockChannelWithTest._test.emit('get_limits', {
        action_type: 'github_sync',
        limit: { allowed: true, message: null },
      });

      // Wait for all limits to be processed
      await waitForCondition(
        () =>
          store.getSnapshot().limits.runs !== undefined &&
          store.getSnapshot().limits.workflow_activation !== undefined &&
          store.getSnapshot().limits.github_sync !== undefined
      );

      const state = store.getSnapshot();
      expect(state.limits.runs).toEqual({ allowed: true, message: null });
      expect(state.limits.workflow_activation).toEqual({
        allowed: false,
        message: 'Workflow limit reached',
      });
      expect(state.limits.github_sync).toEqual({
        allowed: true,
        message: null,
      });

      cleanup();
    });

    test('updates lastUpdated timestamp when limits are received', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      const cleanup = store._connectChannel(mockProvider);

      const initialTimestamp = store.getSnapshot().lastUpdated ?? 0;

      const mockChannelWithTest = mockChannel as MockPhoenixChannel & {
        _test: { emit: (event: string, message: unknown) => void };
      };

      mockChannelWithTest._test.emit('get_limits', {
        action_type: 'activate_workflow',
        limit: { allowed: true, message: null },
      });

      await waitForCondition(() => {
        const lastUpdated = store.getSnapshot().lastUpdated ?? 0;
        return lastUpdated > initialTimestamp;
      });

      const state = store.getSnapshot();
      expect(state.lastUpdated).toBeGreaterThan(initialTimestamp);

      cleanup();
    });
  });

  describe('getLimits command', () => {
    test('supports activate_workflow action type', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      let pushedPayload: any = null;
      mockChannel.push = (event: string, payload: any) => {
        if (event === 'get_limits') {
          pushedPayload = payload;
        }
        return {
          receive: () => ({
            receive: () => ({ receive: () => ({ receive: () => ({}) }) }),
          }),
        };
      };

      const cleanup = store._connectChannel(mockProvider);

      await store.getLimits('activate_workflow');

      expect(pushedPayload).toEqual({ action_type: 'activate_workflow' });

      cleanup();
    });

    test('supports github_sync action type', async () => {
      const store = createSessionContextStore();
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);

      let pushedPayload: any = null;
      mockChannel.push = (event: string, payload: any) => {
        if (event === 'get_limits') {
          pushedPayload = payload;
        }
        return {
          receive: () => ({
            receive: () => ({ receive: () => ({ receive: () => ({}) }) }),
          }),
        };
      };

      const cleanup = store._connectChannel(mockProvider);

      await store.getLimits('github_sync');

      expect(pushedPayload).toEqual({ action_type: 'github_sync' });

      cleanup();
    });

    test('logs warning when no channel is connected', async () => {
      const store = createSessionContextStore();
      const consoleWarnSpy = vi.spyOn(console, 'warn').mockImplementation();

      await store.getLimits('activate_workflow');

      expect(consoleWarnSpy).toHaveBeenCalledWith(
        expect.anything(),
        expect.anything(),
        expect.anything(),
        'Cannot get limits - no channel connected'
      );

      consoleWarnSpy.mockRestore();
    });
  });
});
