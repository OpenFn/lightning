/**
 * Tests for Channel Registry Helpers
 *
 * Covers:
 * - State machine transitions
 * - Channel entry creation
 * - Cleanup timer management
 * - Settling phase with success, timeout, and abort
 * - Channel join with success and error handling
 * - Entry destruction with resource cleanup
 */

import { describe, expect, test, vi, beforeEach, afterEach } from 'vitest';

import type { Channel as PhoenixChannel } from 'phoenix';

import {
  transitionState,
  createChannelEntry,
  scheduleCleanup,
  cancelCleanup,
  startSettling,
  joinChannel,
  destroyEntry,
} from '../../../../js/collaborative-editor/lib/channel-registry/helpers';
import type {
  ChannelEntry,
  ResourceManager,
} from '../../../../js/collaborative-editor/lib/channel-registry/types';

// Mock channel factory
function createMockChannel(topic: string): PhoenixChannel {
  const channel = {
    topic,
    join: vi.fn(() => {
      return {
        receive: vi.fn(function (this: any, status: string, callback: any) {
          // Store callbacks for manual triggering in tests
          if (status === 'ok') {
            this._okCallback = callback;
          } else if (status === 'error') {
            this._errorCallback = callback;
          } else if (status === 'timeout') {
            this._timeoutCallback = callback;
          }
          return this;
        }),
      };
    }),
    leave: vi.fn(),
    on: vi.fn(),
    off: vi.fn(),
    push: vi.fn(),
  } as unknown as PhoenixChannel;

  return channel;
}

describe('Channel Registry Helpers', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  describe('transitionState', () => {
    test('allows valid transition from connecting to settling', () => {
      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'connecting',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const result = transitionState(entry, 'settling');

      expect(result).toBe(true);
      expect(entry.state).toBe('settling');
    });

    test('allows valid transition from connecting to active', () => {
      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'connecting',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const result = transitionState(entry, 'active');

      expect(result).toBe(true);
      expect(entry.state).toBe('active');
    });

    test('allows valid transition from settling to active', () => {
      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'settling',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const result = transitionState(entry, 'active');

      expect(result).toBe(true);
      expect(entry.state).toBe('active');
    });

    test('allows valid transition from active to draining', () => {
      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'active',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const result = transitionState(entry, 'draining');

      expect(result).toBe(true);
      expect(entry.state).toBe('draining');
    });

    test('allows transition to destroyed from any state', () => {
      const states = ['connecting', 'settling', 'active', 'draining'] as const;

      states.forEach(state => {
        const entry: ChannelEntry<null> = {
          topic: 'test:topic',
          state,
          subscribers: new Set(),
          channel: createMockChannel('test:topic'),
          resources: null,
          cleanupTimer: null,
          settlingAbortController: null,
          error: null,
        };

        const result = transitionState(entry, 'destroyed');

        expect(result).toBe(true);
        expect(entry.state).toBe('destroyed');
      });
    });

    test('rejects invalid transition from connecting to draining', () => {
      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'connecting',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const result = transitionState(entry, 'draining');

      expect(result).toBe(false);
      expect(entry.state).toBe('connecting'); // State unchanged
    });

    test('rejects invalid transition from settling to draining', () => {
      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'settling',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const result = transitionState(entry, 'draining');

      expect(result).toBe(false);
      expect(entry.state).toBe('settling'); // State unchanged
    });

    test('rejects any transition from destroyed state', () => {
      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'destroyed',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const result = transitionState(entry, 'active');

      expect(result).toBe(false);
      expect(entry.state).toBe('destroyed'); // State unchanged
    });
  });

  describe('createChannelEntry', () => {
    test('creates entry with correct initial state', () => {
      const topic = 'test:topic';
      const channel = createMockChannel(topic);
      const subscriberId = 'subscriber-1';

      const entry = createChannelEntry(topic, channel, subscriberId, null);

      expect(entry.topic).toBe(topic);
      expect(entry.state).toBe('connecting');
      expect(entry.subscribers.has(subscriberId)).toBe(true);
      expect(entry.subscribers.size).toBe(1);
      expect(entry.channel).toBe(channel);
      expect(entry.resources).toBe(null);
      expect(entry.cleanupTimer).toBe(null);
      expect(entry.settlingAbortController).toBe(null);
      expect(entry.error).toBe(null);
    });

    test('creates entry with resources', () => {
      const topic = 'test:topic';
      const channel = createMockChannel(topic);
      const subscriberId = 'subscriber-1';
      const resources = { data: 'test' };

      const entry = createChannelEntry(topic, channel, subscriberId, resources);

      expect(entry.resources).toBe(resources);
    });
  });

  describe('scheduleCleanup', () => {
    test('schedules cleanup function to run after delay', () => {
      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'draining',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const cleanupFn = vi.fn();
      const delayMs = 2000;

      scheduleCleanup(entry, delayMs, cleanupFn);

      expect(entry.cleanupTimer).not.toBe(null);
      expect(cleanupFn).not.toHaveBeenCalled();

      // Advance time
      vi.advanceTimersByTime(delayMs);

      expect(cleanupFn).toHaveBeenCalledTimes(1);
      expect(entry.cleanupTimer).toBe(null);
    });

    test('cancels previous timer when scheduling new cleanup', () => {
      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'draining',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const firstCleanup = vi.fn();
      const secondCleanup = vi.fn();

      // Schedule first cleanup
      scheduleCleanup(entry, 2000, firstCleanup);
      vi.advanceTimersByTime(1000);

      // Schedule second cleanup before first completes
      scheduleCleanup(entry, 2000, secondCleanup);
      vi.advanceTimersByTime(2000);

      // Only second cleanup should run
      expect(firstCleanup).not.toHaveBeenCalled();
      expect(secondCleanup).toHaveBeenCalledTimes(1);
    });
  });

  describe('cancelCleanup', () => {
    test('cancels pending cleanup timer', () => {
      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'draining',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const cleanupFn = vi.fn();

      scheduleCleanup(entry, 2000, cleanupFn);
      expect(entry.cleanupTimer).not.toBe(null);

      cancelCleanup(entry);
      expect(entry.cleanupTimer).toBe(null);

      vi.advanceTimersByTime(2000);
      expect(cleanupFn).not.toHaveBeenCalled();
    });

    test('does nothing if no timer is scheduled', () => {
      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'active',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      // Should not throw
      cancelCleanup(entry);
      expect(entry.cleanupTimer).toBe(null);
    });
  });

  describe('startSettling', () => {
    test('completes successfully when resources settle', async () => {
      const resources = { ready: false };
      const entry: ChannelEntry<typeof resources> = {
        topic: 'test:topic',
        state: 'settling',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const onComplete = vi.fn();
      const resourceManager: ResourceManager<typeof resources> = {
        create: () => resources,
        destroy: () => {},
        waitForSettled: vi.fn(async () => {
          // Simulate async settling
          await new Promise(resolve => setTimeout(resolve, 100));
        }),
      };

      const settlingPromise = startSettling(
        entry,
        resourceManager,
        10000,
        onComplete
      );

      // Advance timers for settling
      await vi.advanceTimersByTimeAsync(100);
      await settlingPromise;

      expect(resourceManager.waitForSettled).toHaveBeenCalledWith(
        resources,
        expect.any(Object)
      );
      expect(onComplete).toHaveBeenCalledTimes(1);
      expect(entry.settlingAbortController).toBe(null);
    });

    test('handles settling timeout', async () => {
      const resources = { ready: false };
      const entry: ChannelEntry<typeof resources> = {
        topic: 'test:topic',
        state: 'settling',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const onComplete = vi.fn();
      const resourceManager: ResourceManager<typeof resources> = {
        create: () => resources,
        destroy: () => {},
        waitForSettled: vi.fn(async () => {
          // Never resolves
          await new Promise(() => {});
        }),
      };

      const settlingPromise = startSettling(
        entry,
        resourceManager,
        1000,
        onComplete
      );

      // Advance past timeout
      await vi.advanceTimersByTimeAsync(1000);
      await settlingPromise;

      expect(onComplete).not.toHaveBeenCalled();
      expect(entry.error).toContain('Settling timeout');
    });

    test('handles abort signal', async () => {
      const resources = { ready: false };
      const entry: ChannelEntry<typeof resources> = {
        topic: 'test:topic',
        state: 'settling',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const onComplete = vi.fn();
      let capturedAbortSignal: AbortSignal | null = null;
      const resourceManager: ResourceManager<typeof resources> = {
        create: () => resources,
        destroy: () => {},
        waitForSettled: vi.fn(async (_, signal) => {
          capturedAbortSignal = signal;
          await new Promise(resolve => {
            signal.addEventListener('abort', resolve);
          });
        }),
      };

      const settlingPromise = startSettling(
        entry,
        resourceManager,
        10000,
        onComplete
      );

      // Abort the settling
      entry.settlingAbortController?.abort();

      await settlingPromise;

      expect(capturedAbortSignal?.aborted).toBe(true);
      expect(onComplete).not.toHaveBeenCalled();
    });

    test('does nothing if resource manager has no waitForSettled', async () => {
      const resources = { data: 'test' };
      const entry: ChannelEntry<typeof resources> = {
        topic: 'test:topic',
        state: 'settling',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const onComplete = vi.fn();
      const resourceManager: ResourceManager<typeof resources> = {
        create: () => resources,
        destroy: () => {},
        // No waitForSettled method
      };

      await startSettling(entry, resourceManager, 10000, onComplete);

      expect(onComplete).not.toHaveBeenCalled();
    });

    test('does nothing if entry has no resources', async () => {
      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'settling',
        subscribers: new Set(),
        channel: createMockChannel('test:topic'),
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const onComplete = vi.fn();
      const resourceManager: ResourceManager<null> = {
        create: () => null,
        destroy: () => {},
        waitForSettled: vi.fn(async () => {}),
      };

      await startSettling(entry, resourceManager, 10000, onComplete);

      expect(resourceManager.waitForSettled).not.toHaveBeenCalled();
      expect(onComplete).not.toHaveBeenCalled();
    });
  });

  describe('joinChannel', () => {
    test('calls onSuccess when channel joins successfully', () => {
      const onSuccess = vi.fn();
      const onError = vi.fn();

      // Create mock that immediately calls success callback
      const channel = {
        topic: 'test:topic',
        join: vi.fn(() => ({
          receive: (status: string, callback: any) => {
            if (status === 'ok') {
              setTimeout(() => callback({ status: 'ok' }), 0);
            }
            return {
              receive: (s: string, cb: any) => {
                if (s === 'error') {
                  // Not called in success case
                }
                return {
                  receive: () => ({}),
                };
              },
            };
          },
        })),
        leave: vi.fn(),
        on: vi.fn(),
        off: vi.fn(),
        push: vi.fn(),
      } as unknown as PhoenixChannel;

      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'connecting',
        subscribers: new Set(),
        channel,
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      joinChannel(entry, onSuccess, onError);

      expect(channel.join).toHaveBeenCalled();

      // Wait for async callback
      vi.runAllTimers();

      expect(onSuccess).toHaveBeenCalledWith({ status: 'ok' });
      expect(onError).not.toHaveBeenCalled();
      expect(entry.error).toBe(null);
    });

    test('calls onError when channel join fails', () => {
      const onSuccess = vi.fn();
      const onError = vi.fn();

      // Create mock that immediately calls error callback
      const channel = {
        topic: 'test:topic',
        join: vi.fn(() => ({
          receive: (status: string, callback: any) => {
            return {
              receive: (s: string, cb: any) => {
                if (s === 'error') {
                  setTimeout(() => cb({ reason: 'unauthorized' }), 0);
                }
                return {
                  receive: () => ({}),
                };
              },
            };
          },
        })),
        leave: vi.fn(),
        on: vi.fn(),
        off: vi.fn(),
        push: vi.fn(),
      } as unknown as PhoenixChannel;

      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'connecting',
        subscribers: new Set(),
        channel,
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      joinChannel(entry, onSuccess, onError);

      // Wait for async callback
      vi.runAllTimers();

      expect(onError).toHaveBeenCalledWith({ reason: 'unauthorized' });
      expect(onSuccess).not.toHaveBeenCalled();
      expect(entry.error).toContain('Join failed');
    });

    test('calls onError on timeout', () => {
      const onSuccess = vi.fn();
      const onError = vi.fn();

      // Create mock that immediately calls timeout callback
      const channel = {
        topic: 'test:topic',
        join: vi.fn(() => ({
          receive: (status: string, callback: any) => {
            return {
              receive: (s: string, cb: any) => {
                return {
                  receive: (st: string, c: any) => {
                    if (st === 'timeout') {
                      setTimeout(() => c(), 0);
                    }
                    return {};
                  },
                };
              },
            };
          },
        })),
        leave: vi.fn(),
        on: vi.fn(),
        off: vi.fn(),
        push: vi.fn(),
      } as unknown as PhoenixChannel;

      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'connecting',
        subscribers: new Set(),
        channel,
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      joinChannel(entry, onSuccess, onError);

      // Wait for async callback
      vi.runAllTimers();

      expect(onError).toHaveBeenCalledWith(expect.any(Error));
      expect(onSuccess).not.toHaveBeenCalled();
      expect(entry.error).toBe('Join timeout');
    });
  });

  describe('destroyEntry', () => {
    test('destroys entry and leaves channel', () => {
      const channel = createMockChannel('test:topic');
      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'active',
        subscribers: new Set(['sub-1', 'sub-2']),
        channel,
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      destroyEntry(entry, null);

      expect(entry.state).toBe('destroyed');
      expect(channel.leave).toHaveBeenCalled();
      expect(entry.subscribers.size).toBe(0);
    });

    test('destroys resources using resource manager', () => {
      const channel = createMockChannel('test:topic');
      const resources = { data: 'test' };
      const entry: ChannelEntry<typeof resources> = {
        topic: 'test:topic',
        state: 'active',
        subscribers: new Set(),
        channel,
        resources,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const resourceManager: ResourceManager<typeof resources> = {
        create: () => resources,
        destroy: vi.fn(),
      };

      destroyEntry(entry, resourceManager);

      expect(resourceManager.destroy).toHaveBeenCalledWith(resources);
      expect(entry.state).toBe('destroyed');
    });

    test('cancels cleanup timer if scheduled', () => {
      const channel = createMockChannel('test:topic');
      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'draining',
        subscribers: new Set(),
        channel,
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      // Schedule cleanup
      const cleanupFn = vi.fn();
      scheduleCleanup(entry, 2000, cleanupFn);
      expect(entry.cleanupTimer).not.toBe(null);

      // Destroy entry
      destroyEntry(entry, null);

      expect(entry.cleanupTimer).toBe(null);
      vi.advanceTimersByTime(2000);
      expect(cleanupFn).not.toHaveBeenCalled();
    });

    test('aborts settling if in progress', () => {
      const channel = createMockChannel('test:topic');
      const resources = { data: 'test' };
      const entry: ChannelEntry<typeof resources> = {
        topic: 'test:topic',
        state: 'settling',
        subscribers: new Set(),
        channel,
        resources,
        cleanupTimer: null,
        settlingAbortController: new AbortController(),
        error: null,
      };

      const abortSpy = vi.spyOn(entry.settlingAbortController, 'abort');

      destroyEntry(entry, null);

      expect(abortSpy).toHaveBeenCalled();
      expect(entry.settlingAbortController).toBe(null);
    });

    test('handles errors during resource cleanup', () => {
      const channel = createMockChannel('test:topic');
      const resources = { data: 'test' };
      const entry: ChannelEntry<typeof resources> = {
        topic: 'test:topic',
        state: 'active',
        subscribers: new Set(),
        channel,
        resources,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      const resourceManager: ResourceManager<typeof resources> = {
        create: () => resources,
        destroy: vi.fn(() => {
          throw new Error('Destroy failed');
        }),
      };

      // Should not throw
      expect(() => {
        destroyEntry(entry, resourceManager);
      }).not.toThrow();

      expect(entry.state).toBe('destroyed');
    });

    test('handles errors during channel leave', () => {
      const channel = createMockChannel('test:topic');
      channel.leave = vi.fn(() => {
        throw new Error('Leave failed');
      });

      const entry: ChannelEntry<null> = {
        topic: 'test:topic',
        state: 'active',
        subscribers: new Set(),
        channel,
        resources: null,
        cleanupTimer: null,
        settlingAbortController: null,
        error: null,
      };

      // Should not throw
      expect(() => {
        destroyEntry(entry, null);
      }).not.toThrow();

      expect(entry.state).toBe('destroyed');
    });
  });
});
