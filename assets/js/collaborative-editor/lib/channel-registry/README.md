# Channel Registry Infrastructure

This directory contains a reusable infrastructure for managing Phoenix Channel
lifecycles in stores. It provides reference counting, state machine management,
and pluggable resource handling for channels.

## Problem Statement

Managing Phoenix Channel connections in a collaborative editor presents several
challenges:

### 1. Reference Counting

Multiple React components may subscribe to the same channel (e.g., multiple
components rendering workflow state). Without reference counting, the channel
would be destroyed when the first component unmounts, breaking the others.

### 2. Race Conditions During Fast Switching

When switching between workflow versions rapidly, naive implementations create
race conditions:

- Old channel hasn't finished cleanup yet
- New channel tries to join with same topic
- Both channels receive updates, causing state conflicts

### 3. Flickering During Version Transitions

Without a settling phase, the UI can flicker when switching versions:

- Channel joins immediately
- Empty Y.Doc state renders briefly
- Server sync arrives and populates state
- UI jumps from empty → populated

### 4. Resource Management Complexity

Different channel types need different resources:

- Collaborative channels need Y.Doc, Provider, and Awareness
- AI assistant channels need simpler state
- Future channel types may need other resources

This infrastructure solves these problems by providing:

1. **Reference counting** - Multiple subscribers can safely share a channel
2. **5-state machine** - Controlled transitions prevent race conditions
3. **Optional settling phase** - Wait for readiness before activating
4. **Pluggable resources** - `ResourceManager<T>` interface for any resource
   type

## Architecture Overview

The channel registry uses a **state machine** to manage channel lifecycle,
**reference counting** to track subscribers, and **pluggable resource managers**
to handle channel-specific resources.

```
┌─────────────────────────────────────────────────────────────┐
│                     Channel Entry                           │
├─────────────────────────────────────────────────────────────┤
│ topic: "workflow:v123"                                      │
│ state: connecting → settling → active → draining → destroyed│
│ subscribers: Set<string> (component IDs)                    │
│ channel: PhoenixChannel                                     │
│ resources: TResources | null (Y.Doc, Awareness, etc.)       │
│ cleanupTimer: NodeJS.Timeout | null                         │
│ settlingAbortController: AbortController | null             │
└─────────────────────────────────────────────────────────────┘
```

### State Machine

The channel lifecycle follows a strict state machine with validated transitions:

```
connecting ──┬──> settling ──┬──> active ──┬──> draining ──> destroyed
             │               │             │
             └───────────────┴─────────────┘
                (all states can go directly to destroyed)
```

**State Transitions:**

```
connecting → settling   (if ResourceManager has waitForSettled)
connecting → active     (if no settling needed)
connecting → destroyed  (error during join)

settling → active       (settling complete)
settling → destroyed    (timeout or abort)

active → draining       (new channel supersedes this one)
active → destroyed      (immediate cleanup)

draining → destroyed    (grace period elapsed, typically 2s)

destroyed → (none)      (terminal state)
```

### Reference Counting

Multiple components can subscribe to the same channel:

```typescript
// Component A subscribes
entry.subscribers.add('component-a-id'); // size: 1

// Component B subscribes
entry.subscribers.add('component-b-id'); // size: 2

// Component A unsubscribes
entry.subscribers.delete('component-a-id'); // size: 1, keep channel alive

// Component B unsubscribes
entry.subscribers.delete('component-b-id'); // size: 0, cleanup channel
```

When the last subscriber leaves, the channel enters the `draining` state with a
2-second grace period before cleanup. This prevents thrashing if a new
subscriber arrives quickly.

### Pluggable Resources

The `ResourceManager<TResources>` interface allows different channel types to
manage their own resources:

```typescript
interface ResourceManager<TResources> {
  // Create resources when channel is created
  create(channel: PhoenixChannel): TResources;

  // Destroy resources when channel is cleaned up
  destroy(resources: TResources): void;

  // Optional: Wait for resources to be ready before activating
  waitForSettled?(
    resources: TResources,
    abortSignal: AbortSignal
  ): Promise<void>;
}
```

## State Machine Reference

### State Descriptions

#### `connecting`

**Purpose:** Channel join is in progress.

**Entry:** When a new channel is created and join is initiated.

**Exit:** Transitions to `settling` (if ResourceManager has waitForSettled),
`active` (if no settling), or `destroyed` (on error).

**Operations:**

- Channel.join() called
- Resources created (if ResourceManager provided)
- Waiting for join response

#### `settling`

**Purpose:** Channel joined successfully, waiting for resources to be ready.

**Entry:** After successful join when ResourceManager has `waitForSettled`
method.

**Exit:** Transitions to `active` (when settled) or `destroyed` (on
timeout/abort).

**Operations:**

- ResourceManager.waitForSettled() called with 10s timeout
- AbortController can cancel settling
- Prevents UI flickering by waiting for initial sync

**Use Cases:**

- Yjs channels: Wait for first Y.Doc update from server
- AI assistant channels: Wait for initial context load
- Any channel needing pre-activation readiness

#### `active`

**Purpose:** Channel is fully operational and ready for use.

**Entry:** After successful join (no settling) or after settling completes.

**Exit:** Transitions to `draining` (superseded by new channel) or `destroyed`
(immediate cleanup).

**Operations:**

- All resources ready
- Components can read/write through channel
- Normal message flow

#### `draining`

**Purpose:** Channel superseded by newer version, awaiting final cleanup.

**Entry:** When a new channel joins with the same topic while this one is
`active`.

**Exit:** Transitions to `destroyed` after grace period (typically 2s).

**Operations:**

- 2-second grace period before cleanup
- Channel still functional during draining
- Prevents race conditions with overlapping channels
- Grace period can be cancelled if new subscriber arrives

#### `destroyed`

**Purpose:** Resources released, channel left.

**Entry:** Terminal state reached through various paths.

**Exit:** None (terminal state).

**Operations:**

- Resources destroyed via ResourceManager
- Channel.leave() called
- All timers cancelled
- Subscribers cleared

### State Transition Table

| From       | To         | Trigger                                  | Valid? |
| ---------- | ---------- | ---------------------------------------- | ------ |
| connecting | settling   | Join succeeded + has waitForSettled      | ✅     |
| connecting | active     | Join succeeded + no waitForSettled       | ✅     |
| connecting | destroyed  | Join failed or immediate cleanup         | ✅     |
| connecting | draining   | -                                        | ❌     |
| settling   | active     | Settling complete                        | ✅     |
| settling   | destroyed  | Settling timeout or abort                | ✅     |
| settling   | draining   | -                                        | ❌     |
| settling   | connecting | -                                        | ❌     |
| active     | draining   | New channel supersedes                   | ✅     |
| active     | destroyed  | Immediate cleanup (last subscriber left) | ✅     |
| active     | settling   | -                                        | ❌     |
| active     | connecting | -                                        | ❌     |
| draining   | destroyed  | Grace period elapsed                     | ✅     |
| draining   | active     | -                                        | ❌     |
| draining   | settling   | -                                        | ❌     |
| draining   | connecting | -                                        | ❌     |
| destroyed  | (any)      | -                                        | ❌     |

### When Settling Is Used vs Skipped

**Settling is used when:**

- ResourceManager implements `waitForSettled` method
- Channel needs initial data before becoming active
- Want to prevent UI flickering during initial sync

**Settling is skipped when:**

- ResourceManager doesn't implement `waitForSettled`
- Channel is immediately usable after join
- No initialization wait required

**Examples:**

```typescript
// With settling (Yjs channels)
const yjsManager: ResourceManager<YjsResources> = {
  create: channel => ({ ydoc, provider, awareness }),
  destroy: resources => {
    /* cleanup */
  },
  waitForSettled: async (resources, signal) => {
    // Wait for first Y.Doc update
    await waitForFirstUpdate(resources.ydoc, signal);
  },
};

// Without settling (simple channels)
const simpleManager: ResourceManager<null> = {
  create: () => null,
  destroy: () => {},
  // No waitForSettled - skip settling phase
};
```

## Usage Patterns

### Basic Store Integration

A store using the channel registry typically has:

1. A registry map: `Map<string, ChannelEntry<TResources>>`
2. Subscribe/unsubscribe methods for components
3. Helper functions from this library for state management

```typescript
import {
  createChannelEntry,
  transitionState,
  joinChannel,
  startSettling,
  scheduleCleanup,
  destroyEntry,
} from './channel-registry';

interface MyStore {
  registry: Map<string, ChannelEntry<MyResources>>;
  subscribe: (subscriberId: string, topic: string) => void;
  unsubscribe: (subscriberId: string, topic: string) => void;
}
```

### Example: Subscribe Method

```typescript
subscribe(subscriberId: string, topic: string): void {
  let entry = this.registry.get(topic);

  if (entry) {
    // Channel exists - add subscriber
    entry.subscribers.add(subscriberId);

    // If draining, cancel cleanup and reactivate
    if (entry.state === 'draining') {
      cancelCleanup(entry);
      transitionState(entry, 'active');
    }
  } else {
    // Create new channel
    const channel = socket.channel(topic, params);
    const resources = resourceManager.create(channel);
    entry = createChannelEntry(topic, channel, subscriberId, resources);

    this.registry.set(topic, entry);

    // Join channel
    joinChannel(
      entry,
      (response) => this.handleJoinSuccess(entry, response),
      (error) => this.handleJoinError(entry, error)
    );
  }
}

handleJoinSuccess(entry: ChannelEntry<MyResources>, response: unknown): void {
  // If has settling phase
  if (resourceManager.waitForSettled && entry.resources) {
    transitionState(entry, 'settling');
    startSettling(
      entry,
      resourceManager,
      10000, // timeout
      () => {
        transitionState(entry, 'active');
        this.notifySubscribers();
      }
    );
  } else {
    // No settling - go directly active
    transitionState(entry, 'active');
    this.notifySubscribers();
  }
}
```

### Example: Unsubscribe Method

```typescript
unsubscribe(subscriberId: string, topic: string): void {
  const entry = this.registry.get(topic);
  if (!entry) return;

  // Remove subscriber
  entry.subscribers.delete(subscriberId);

  // If last subscriber, start draining
  if (entry.subscribers.size === 0 && entry.state === 'active') {
    transitionState(entry, 'draining');
    scheduleCleanup(entry, 2000, () => {
      destroyEntry(entry, resourceManager);
      this.registry.delete(topic);
    });
  }
}
```

### Example: Version Migration (migrateToRoom)

When switching between workflow versions, use the draining state to prevent race
conditions:

```typescript
migrateToRoom(newTopic: string): void {
  const currentEntry = this.getCurrentEntry();

  // Put current channel in draining state
  if (currentEntry && currentEntry.state === 'active') {
    transitionState(currentEntry, 'draining');
    scheduleCleanup(currentEntry, 2000, () => {
      destroyEntry(currentEntry, resourceManager);
      this.registry.delete(currentEntry.topic);
    });
  }

  // Subscribe to new channel
  this.subscribe(componentId, newTopic);
}
```

This pattern ensures:

- Old channel stays alive during transition (2s grace period)
- New channel can start joining immediately
- No race conditions between overlapping channels
- Smooth transition without flickering

## Code Examples

### Creating a Channel Entry

```typescript
import { createChannelEntry } from './channel-registry';

const topic = 'workflow:v123';
const channel = socket.channel(topic, { user_id: 'abc' });
const subscriberId = React.useId(); // Component ID
const resources = resourceManager.create(channel);

const entry = createChannelEntry(topic, channel, subscriberId, resources);
// entry.state === 'connecting'
// entry.subscribers.size === 1
```

### Managing Subscribers

```typescript
import { transitionState, cancelCleanup } from './channel-registry';

// Add subscriber
entry.subscribers.add(newSubscriberId);

// If channel was draining, reactivate it
if (entry.state === 'draining') {
  cancelCleanup(entry);
  transitionState(entry, 'active');
}

// Remove subscriber
entry.subscribers.delete(subscriberId);

// If last subscriber left, start draining
if (entry.subscribers.size === 0 && entry.state === 'active') {
  transitionState(entry, 'draining');
  scheduleCleanup(entry, 2000, () => {
    // Cleanup callback
  });
}
```

### Handling Settling Phase

```typescript
import { startSettling, transitionState } from './channel-registry';

// After successful channel join
if (resourceManager.waitForSettled && entry.resources) {
  transitionState(entry, 'settling');

  await startSettling(
    entry,
    resourceManager,
    10000, // 10s timeout
    () => {
      // Settling complete
      transitionState(entry, 'active');
      notifyComponents();
    }
  );
} else {
  // No settling needed
  transitionState(entry, 'active');
  notifyComponents();
}
```

### Cleanup Patterns

```typescript
import { destroyEntry } from './channel-registry';

// Immediate cleanup
if (entry.state !== 'destroyed') {
  destroyEntry(entry, resourceManager);
  registry.delete(topic);
}

// Delayed cleanup (draining)
if (entry.state === 'active') {
  transitionState(entry, 'draining');
  scheduleCleanup(entry, 2000, () => {
    destroyEntry(entry, resourceManager);
    registry.delete(topic);
  });
}
```

## ResourceManager Interface

### Built-in Resource Managers

#### `noopResourceManager`

For simple channels without resources (e.g., AI assistant channels):

```typescript
import { noopResourceManager } from './channel-registry';

const noopManager: ResourceManager<null> = {
  create: () => null,
  destroy: () => {},
};
```

**Use cases:**

- Channels that only send/receive messages
- No persistent state needed
- No settling phase required

#### `YjsResources` (Future)

For collaborative channels with Y.Doc and Awareness:

```typescript
interface YjsResources {
  ydoc: Doc; // Y.Doc instance
  provider: PhoenixChannelProvider; // Sync provider
  awareness: Awareness; // Presence protocol
}

// Will be implemented in Phase 3
// const yjsManager = createYjsResourceManager({
//   syncTimeout: 10000,
//   requireFirstUpdate: true,
// });
```

**Use cases:**

- Collaborative workflow editing
- Real-time document sync
- User presence tracking
- Requires settling phase to wait for initial sync

### Implementing Custom Resource Managers

```typescript
import type { ResourceManager } from './channel-registry';

interface MyResources {
  connection: WebSocket;
  cache: Map<string, unknown>;
}

const myResourceManager: ResourceManager<MyResources> = {
  create: channel => {
    return {
      connection: new WebSocket('...'),
      cache: new Map(),
    };
  },

  destroy: resources => {
    resources.connection.close();
    resources.cache.clear();
  },

  // Optional: Wait for connection to be ready
  waitForSettled: async (resources, signal) => {
    return new Promise((resolve, reject) => {
      resources.connection.onopen = () => resolve();
      resources.connection.onerror = err => reject(err);

      signal.addEventListener('abort', () => {
        reject(new Error('Aborted'));
      });
    });
  },
};
```

**Implementation guidelines:**

- `create`: Initialize resources, attach event handlers
- `destroy`: Clean up resources, remove handlers, close connections
- `waitForSettled`: Optional, wait for resources to be ready
  - Must respect `abortSignal` for cancellation
  - Should have reasonable timeout (handled by caller)
  - Can throw errors that will be caught and logged

## Testing Guidance

### Testing Stores with Channel Registry

When testing stores that use the channel registry:

1. **Mock Phoenix Channels:**

```typescript
import { vi } from 'vitest';
import type { Channel as PhoenixChannel } from 'phoenix';

function createMockChannel(topic: string): PhoenixChannel {
  return {
    topic,
    join: vi.fn(() => ({
      receive: vi.fn(function (status, callback) {
        if (status === 'ok') {
          setTimeout(() => callback({ status: 'ok' }), 0);
        }
        return { receive: vi.fn(() => ({ receive: vi.fn() })) };
      }),
    })),
    leave: vi.fn(),
    on: vi.fn(),
    off: vi.fn(),
    push: vi.fn(),
  } as unknown as PhoenixChannel;
}
```

2. **Mock Resource Managers:**

```typescript
const mockResourceManager: ResourceManager<MockResources> = {
  create: vi.fn(() => ({ data: 'test' })),
  destroy: vi.fn(),
  waitForSettled: vi.fn(async () => {
    await new Promise(resolve => setTimeout(resolve, 100));
  }),
};
```

3. **Use Fake Timers:**

```typescript
import { beforeEach, afterEach } from 'vitest';

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

// Test with timers
test('cleanup after grace period', () => {
  store.unsubscribe('sub-1', topic);

  expect(entry.state).toBe('draining');

  vi.advanceTimersByTime(2000);

  expect(entry.state).toBe('destroyed');
});
```

### Testing State Machine Transitions

```typescript
import { transitionState } from './channel-registry';

test('valid state transitions', () => {
  const entry = createChannelEntry(topic, channel, 'sub-1', null);

  // connecting → active (valid)
  expect(transitionState(entry, 'active')).toBe(true);
  expect(entry.state).toBe('active');

  // active → connecting (invalid)
  expect(transitionState(entry, 'connecting')).toBe(false);
  expect(entry.state).toBe('active'); // unchanged
});
```

### Testing Settling Phase

```typescript
test('settling completes successfully', async () => {
  const entry = createChannelEntry(topic, channel, 'sub-1', resources);
  entry.state = 'settling';

  const onComplete = vi.fn();

  const promise = startSettling(entry, mockResourceManager, 10000, onComplete);

  // Advance time for settling
  await vi.advanceTimersByTimeAsync(100);
  await promise;

  expect(onComplete).toHaveBeenCalledTimes(1);
  expect(entry.settlingAbortController).toBe(null);
});

test('settling timeout', async () => {
  const neverResolveManager: ResourceManager<unknown> = {
    create: () => ({}),
    destroy: () => {},
    waitForSettled: async () => {
      await new Promise(() => {}); // Never resolves
    },
  };

  const entry = createChannelEntry(topic, channel, 'sub-1', {});
  const onComplete = vi.fn();

  const promise = startSettling(entry, neverResolveManager, 1000, onComplete);

  await vi.advanceTimersByTimeAsync(1000);
  await promise;

  expect(onComplete).not.toHaveBeenCalled();
  expect(entry.error).toContain('Settling timeout');
});
```

### Testing Reference Counting

```typescript
test('multiple subscribers keep channel alive', () => {
  // First subscriber
  store.subscribe('sub-1', topic);
  const entry = store.registry.get(topic);
  expect(entry?.subscribers.size).toBe(1);

  // Second subscriber
  store.subscribe('sub-2', topic);
  expect(entry?.subscribers.size).toBe(2);

  // First unsubscribes - channel stays active
  store.unsubscribe('sub-1', topic);
  expect(entry?.subscribers.size).toBe(1);
  expect(entry?.state).toBe('active');

  // Last unsubscribes - channel starts draining
  store.unsubscribe('sub-2', topic);
  expect(entry?.subscribers.size).toBe(0);
  expect(entry?.state).toBe('draining');
});
```

## Configuration

The registry behavior can be configured through `ChannelRegistryConfig`:

```typescript
interface ChannelRegistryConfig<TResources, TContext> {
  name: string; // For logging
  cleanupDelayMs?: number; // Default: 2000ms
  settlingTimeoutMs?: number; // Default: 10000ms

  // Lifecycle callbacks
  onStateChange?: (topic, state, entry) => void;
  onJoinSuccess?: (topic, response, entry) => void;
  onJoinError?: (topic, error, entry) => void;
  onMessage?: (topic, event, payload) => void;

  // Channel setup
  buildJoinParams?: (context: TContext) => Record<string, unknown>;
  setupEventHandlers?: (channel, topic) => () => void;
}
```

**Common configurations:**

```typescript
// Fast cleanup (testing)
const testConfig = {
  name: 'TestStore',
  cleanupDelayMs: 100,
  settlingTimeoutMs: 1000,
};

// Production with callbacks
const prodConfig = {
  name: 'WorkflowStore',
  cleanupDelayMs: 2000,
  settlingTimeoutMs: 10000,
  onStateChange: (topic, state) => {
    logger.info('Channel state changed', { topic, state });
  },
  onJoinError: (topic, error) => {
    showToast({ type: 'error', message: 'Failed to join channel' });
  },
};
```

## Related Documentation

- [Store Structure](../../../.claude/guidelines/store-structure.md) -
  Collaborative editor store architecture
- [Testing Essentials](../../../.claude/guidelines/testing-essentials.md) - Unit
  testing patterns
- [Yex Guidelines](../../../.claude/guidelines/yex-guidelines.md) - Yjs/Elixir
  integration

## Implementation Notes

### Why 2-Second Grace Period?

The 2-second grace period in the `draining` state serves multiple purposes:

1. **Fast switching tolerance** - Users clicking through versions quickly won't
   create channel thrashing
2. **Race condition buffer** - Gives old channel time to finish cleanup before
   new one starts
3. **Network latency cushion** - Accounts for slow connections or server delays
4. **Component remounting** - React StrictMode or fast refresh won't cause
   cleanup/recreation cycles

### Why Optional Settling Phase?

Not all channels need a settling phase:

- **Simple channels** - Immediately usable after join (AI assistant,
  notifications)
- **Collaborative channels** - Need to wait for initial sync to prevent
  flickering
- **Performance trade-off** - Settling adds latency, only use when necessary

### Why Pluggable Resources?

Different channel types have different needs:

- **Yjs channels** - Need Y.Doc, Provider, Awareness instances
- **AI channels** - May need conversation history cache
- **Notification channels** - May need simple message queue
- **Future channels** - Unknown requirements, but architecture supports them

The `ResourceManager<T>` pattern allows each channel type to manage its own
resources without coupling the registry to specific implementations.
