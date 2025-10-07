# Lightning Collaborative Editor Testing Patterns

Testing patterns specific to Lightning's collaborative workflow editor, including Yjs integration, Phoenix Channels, and real-time synchronization.

## Overview

The Lightning collaborative editor combines:
- **Yjs** - CRDT for real-time document synchronization
- **Phoenix Channels** - WebSocket communication layer
- **React stores** - Client-side state management
- **Y-Phoenix-Channel** - Yjs + Phoenix integration

## Testing Yjs Integration

### Testing Document Synchronization

**✅ DO: Test document synchronization**

```typescript
test('ydoc syncs changes between instances', () => {
  const store1 = createSessionStore();
  const store2 = createSessionStore();

  const ydoc1 = store1.initializeYDoc();
  const ydoc2 = store2.initializeYDoc();

  // Apply update from doc1 to doc2
  const update = encodeStateAsUpdate(ydoc1);
  applyUpdate(ydoc2, update);

  expect(encodeStateAsUpdate(ydoc2)).toEqual(update);
});
```

**✅ DO: Test Yjs array operations**

```typescript
test('handles job insertions in Yjs array', () => {
  const store = createSessionStore();
  const ydoc = store.initializeYDoc();
  const jobs = ydoc.getArray('jobs');

  // Add jobs
  jobs.push([
    { id: 'job1', name: 'Test Job 1' },
    { id: 'job2', name: 'Test Job 2' },
  ]);

  expect(jobs.length).toBe(2);
  expect(jobs.get(0)).toMatchObject({ id: 'job1' });
});
```

**✅ DO: Test Yjs map operations**

```typescript
test('updates workflow metadata in Yjs map', () => {
  const ydoc = new Y.Doc();
  const workflow = ydoc.getMap('workflow');

  workflow.set('name', 'My Workflow');
  workflow.set('project_id', 'project-123');

  expect(workflow.get('name')).toBe('My Workflow');
  expect(workflow.get('project_id')).toBe('project-123');
});
```

### Testing Yjs Observability

**✅ DO: Test Yjs observers**

```typescript
test('observes changes to Yjs document', () => {
  const ydoc = new Y.Doc();
  const jobs = ydoc.getArray('jobs');
  const updates: any[] = [];

  jobs.observe((event) => {
    updates.push(event.changes);
  });

  jobs.push([{ id: 'job1', name: 'Test' }]);

  expect(updates).toHaveLength(1);
  expect(updates[0].added).toHaveLength(1);
});
```

## Testing Phoenix Channel Events

### Testing Real-time Event Handling

**✅ DO: Test Phoenix channel message handling**

```typescript
test('handles adaptors_updated event from server', async () => {
  const store = createAdaptorStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  store._connectChannel(mockProvider);

  // Simulate server event
  mockChannel._test.emit('adaptors_updated', mockAdaptorsList);

  await waitFor(() => {
    expect(store.getSnapshot().adaptors).toEqual(mockAdaptorsList);
  });
});
```

**✅ DO: Test channel connection lifecycle**

```typescript
test('handles channel connection and disconnection', async () => {
  const store = createSessionStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  // Connect
  store.initializeSession(mockSocket, 'workflow:123', userData);

  await waitFor(() => {
    expect(store.getSnapshot().isConnected).toBe(true);
  });

  // Disconnect
  act(() => {
    mockChannel._test.emit('presence_diff', { leaves: {} });
  });

  await waitFor(() => {
    expect(store.getSnapshot().isConnected).toBe(false);
  });
});
```

**✅ DO: Test channel error handling**

```typescript
test('handles channel errors gracefully', async () => {
  const store = createAdaptorStore();
  const mockChannel = createMockPhoenixChannel();

  mockChannel.push = () => ({
    receive: (status: string, callback: (resp?: unknown) => void) => {
      if (status === 'error') {
        callback({ reason: 'Network error' });
      }
      return this;
    },
  });

  store._connectChannel(mockChannel);
  await store.requestAdaptors();

  const state = store.getSnapshot();
  expect(state.error).toContain('Network error');
  expect(state.isLoading).toBe(false);
});
```

### Testing Phoenix Presence

**✅ DO: Test presence tracking**

```typescript
test('tracks user presence in collaborative session', async () => {
  const store = createSessionStore();
  const mockChannel = createMockPhoenixChannel();

  store.initializeSession(mockSocket, 'workflow:123', {
    id: 'user1',
    name: 'Test User',
  });

  // Simulate presence state from server
  act(() => {
    mockChannel._test.emit('presence_state', {
      user1: { metas: [{ online_at: Date.now() }] },
      user2: { metas: [{ online_at: Date.now() }] },
    });
  });

  await waitFor(() => {
    const presence = store.getSnapshot().presence;
    expect(Object.keys(presence)).toHaveLength(2);
  });
});
```

## Testing Store Subscriptions

### Testing Subscription Notifications

**✅ DO: Test subscription notifications**

```typescript
test('notifies subscribers on state change', () => {
  const store = createSessionStore();
  const updates: SessionState[] = [];

  const unsubscribe = store.subscribe(() => {
    updates.push(store.getSnapshot());
  });

  store.initializeYDoc();
  store.initializeSession(mockSocket, 'test:room', userData);

  expect(updates).toHaveLength(2);
  expect(updates[0].ydoc).toBeDefined();
  expect(updates[1].provider).toBeDefined();

  unsubscribe();
});
```

**✅ DO: Test selective subscriptions**

```typescript
test('only notifies when subscribed fields change', () => {
  const store = createAdaptorStore();
  let notificationCount = 0;

  const unsubscribe = store.subscribe(
    (state) => state.isLoading,
    () => {
      notificationCount++;
    }
  );

  // This should trigger notification
  store.setLoading(true);
  expect(notificationCount).toBe(1);

  // This should NOT trigger notification (different field)
  store.setError('Some error');
  expect(notificationCount).toBe(1); // Still 1

  unsubscribe();
});
```

## Testing Collaborative Features

### Testing Conflict Resolution

**✅ DO: Test concurrent edits**

```typescript
test('handles concurrent job edits from multiple users', () => {
  const ydoc1 = new Y.Doc();
  const ydoc2 = new Y.Doc();

  const jobs1 = ydoc1.getArray('jobs');
  const jobs2 = ydoc2.getArray('jobs');

  // User 1 adds job
  jobs1.push([{ id: 'job1', name: 'Job from User 1' }]);

  // User 2 adds job (before seeing User 1's change)
  jobs2.push([{ id: 'job2', name: 'Job from User 2' }]);

  // Sync documents
  const update1 = Y.encodeStateAsUpdate(ydoc1);
  const update2 = Y.encodeStateAsUpdate(ydoc2);

  Y.applyUpdate(ydoc1, update2);
  Y.applyUpdate(ydoc2, update1);

  // Both documents should have both jobs
  expect(jobs1.length).toBe(2);
  expect(jobs2.length).toBe(2);
});
```

### Testing Undo/Redo

**✅ DO: Test undo manager**

```typescript
test('supports undo/redo for job edits', () => {
  const ydoc = new Y.Doc();
  const jobs = ydoc.getArray('jobs');
  const undoManager = new Y.UndoManager(jobs);

  // Add job
  jobs.push([{ id: 'job1', name: 'Initial Name' }]);

  // Modify job
  const job = jobs.get(0);
  job.name = 'Updated Name';

  expect(jobs.get(0).name).toBe('Updated Name');

  // Undo
  undoManager.undo();
  expect(jobs.get(0).name).toBe('Initial Name');

  // Redo
  undoManager.redo();
  expect(jobs.get(0).name).toBe('Updated Name');
});
```

## Testing Lightning-Specific Patterns

### Testing Workflow State Management

**✅ DO: Test workflow lock version**

```typescript
test('increments lock version on workflow changes', async () => {
  const store = createWorkflowStore();

  const initialVersion = store.getSnapshot().lockVersion;

  act(() => {
    store.updateWorkflowName('New Workflow Name');
  });

  await waitFor(() => {
    expect(store.getSnapshot().lockVersion).toBe(initialVersion + 1);
  });
});
```

**✅ DO: Test optimistic locking conflicts**

```typescript
test('detects and handles optimistic locking conflicts', async () => {
  const store = createWorkflowStore();

  // Simulate stale lock version
  const staleVersion = store.getSnapshot().lockVersion;

  // Server increments version
  act(() => {
    mockChannel._test.emit('workflow_updated', {
      lock_version: staleVersion + 1,
    });
  });

  // Attempt to save with stale version
  const result = await store.saveWorkflow(staleVersion);

  expect(result.error).toContain('Conflict');
  expect(result.needsRefresh).toBe(true);
});
```

### Testing Adaptor Integration

**✅ DO: Test adaptor version resolution**

```typescript
test('resolves adaptor versions correctly', () => {
  const store = createAdaptorStore();

  store.setAdaptors([
    {
      name: '@openfn/language-http',
      versions: [
        { version: '2.1.0' },
        { version: '2.0.5' },
        { version: '2.0.0' },
      ],
      latest: '2.1.0',
    },
  ]);

  const adaptor = store.findAdaptorByName('@openfn/language-http');

  expect(adaptor?.latest).toBe('2.1.0');
  expect(adaptor?.versions).toHaveLength(3);
});
```

### Testing Credential Management

**✅ DO: Test credential selection**

```typescript
test('filters credentials by project', () => {
  const store = createCredentialStore();

  store.setCredentials([
    { id: 'cred1', project_id: 'proj1', name: 'Cred 1' },
    { id: 'cred2', project_id: 'proj2', name: 'Cred 2' },
    { id: 'cred3', project_id: 'proj1', name: 'Cred 3' },
  ]);

  const projectCreds = store.getCredentialsByProject('proj1');

  expect(projectCreds).toHaveLength(2);
  expect(projectCreds.map(c => c.id)).toEqual(['cred1', 'cred3']);
});
```

## Mock Factories for Lightning

### Phoenix Channel Mock

```typescript
// __helpers__/phoenixMocks.ts
export function createMockPhoenixChannel(topic = 'workflow:test') {
  const eventHandlers = new Map<string, Set<Function>>();
  const mockChannel = {
    topic,
    on(event: string, handler: Function) {
      if (!eventHandlers.has(event)) {
        eventHandlers.set(event, new Set());
      }
      eventHandlers.get(event)!.add(handler);
      return mockChannel;
    },
    off(event: string, handler: Function) {
      eventHandlers.get(event)?.delete(handler);
      return mockChannel;
    },
    push(event: string, payload: any) {
      return {
        receive(status: string, callback: Function) {
          if (status === 'ok') {
            setTimeout(() => callback({ status: 'ok' }), 0);
          }
          return this;
        },
      };
    },
    leave() {
      return this;
    },
    // Test utilities
    _test: {
      emit(event: string, payload: any) {
        const handlers = eventHandlers.get(event);
        if (handlers) {
          handlers.forEach(handler => handler(payload));
        }
      },
      getHandlers(event: string) {
        return Array.from(eventHandlers.get(event) || []);
      },
    },
  };
  return mockChannel;
}
```

### Yjs Document Mock

```typescript
// __helpers__/yjsMocks.ts
export function createMockYDoc(initialData: any = {}) {
  const doc = new Y.Doc();

  // Initialize with data
  if (initialData.jobs) {
    const jobs = doc.getArray('jobs');
    jobs.push(initialData.jobs);
  }

  if (initialData.workflow) {
    const workflow = doc.getMap('workflow');
    Object.entries(initialData.workflow).forEach(([key, value]) => {
      workflow.set(key, value);
    });
  }

  return doc;
}
```

## Integration Testing Patterns

### Testing Full Collaborative Flow

**✅ DO: Test complete collaborative editing flow**

```typescript
test('complete collaborative editing flow', async () => {
  // Setup two users
  const user1Store = createSessionStore();
  const user2Store = createSessionStore();

  const user1Channel = createMockPhoenixChannel();
  const user2Channel = createMockPhoenixChannel();

  // Initialize sessions
  user1Store.initializeSession(mockSocket, 'workflow:123', {
    id: 'user1',
    name: 'User 1',
  });

  user2Store.initializeSession(mockSocket, 'workflow:123', {
    id: 'user2',
    name: 'User 2',
  });

  // User 1 adds a job
  act(() => {
    const jobs = user1Store.getSnapshot().ydoc?.getArray('jobs');
    jobs?.push([{ id: 'job1', name: 'New Job' }]);
  });

  // Simulate sync to user 2
  const update = Y.encodeStateAsUpdate(user1Store.getSnapshot().ydoc!);
  act(() => {
    Y.applyUpdate(user2Store.getSnapshot().ydoc!, update);
  });

  await waitFor(() => {
    const user2Jobs = user2Store.getSnapshot().ydoc?.getArray('jobs');
    expect(user2Jobs?.length).toBe(1);
    expect(user2Jobs?.get(0)).toMatchObject({ id: 'job1' });
  });
});
```

## Performance Testing

### Testing Large Document Performance

**✅ DO: Test performance with large workflows**

```typescript
test('handles large workflow with many jobs', () => {
  const store = createSessionStore();
  const ydoc = store.initializeYDoc();
  const jobs = ydoc.getArray('jobs');

  // Add 1000 jobs
  const manyJobs = Array.from({ length: 1000 }, (_, i) => ({
    id: `job${i}`,
    name: `Job ${i}`,
    body: 'console.log("test");',
  }));

  const startTime = performance.now();
  jobs.push(manyJobs);
  const endTime = performance.now();

  expect(jobs.length).toBe(1000);
  expect(endTime - startTime).toBeLessThan(100); // Should be fast
});
```

## Debugging Helpers

### Logging Yjs Updates

```typescript
// __helpers__/yjsDebug.ts
export function logYjsUpdates(ydoc: Y.Doc) {
  ydoc.on('update', (update: Uint8Array, origin: any) => {
    console.log('Yjs Update:', {
      size: update.length,
      origin: origin?.constructor?.name || origin,
      timestamp: new Date().toISOString(),
    });
  });
}

// Usage in tests
test('debug yjs updates', () => {
  const ydoc = new Y.Doc();
  logYjsUpdates(ydoc);

  const jobs = ydoc.getArray('jobs');
  jobs.push([{ id: 'job1', name: 'Test' }]);
  // Console will show update details
});
```

## Common Pitfalls

### 1. Not Waiting for Async Channel Operations

**❌ DON'T:**
```typescript
test('bad async test', () => {
  store.requestAdaptors(); // Async operation
  expect(store.getSnapshot().adaptors).toHaveLength(3); // Fails - too early
});
```

**✅ DO:**
```typescript
test('good async test', async () => {
  store.requestAdaptors();
  await waitFor(() => {
    expect(store.getSnapshot().adaptors).toHaveLength(3);
  });
});
```

### 2. Forgetting to Clean Up Subscriptions

**❌ DON'T:**
```typescript
test('memory leak', () => {
  const store = createSessionStore();
  store.subscribe(() => {
    // Handler never unsubscribed
  });
  // Store persists with active subscription
});
```

**✅ DO:**
```typescript
test('proper cleanup', () => {
  const store = createSessionStore();
  const unsubscribe = store.subscribe(() => {});

  // Test logic

  unsubscribe();
});
```

### 3. Not Wrapping Channel Events in act()

**❌ DON'T:**
```typescript
test('channel event without act', async () => {
  mockChannel.emit('session_context', { user: mockUser });
  // React warning: "update not wrapped in act()"
});
```

**✅ DO:**
```typescript
test('channel event with act', async () => {
  act(() => {
    mockChannel.emit('session_context', { user: mockUser });
  });

  await waitFor(() => {
    expect(result.current.user).toEqual(mockUser);
  });
});
```

## Additional Resources

- [Yjs Documentation](https://docs.yjs.dev/)
- [Phoenix Channels Guide](https://hexdocs.pm/phoenix/channels.html)
- [Y-Phoenix-Channel](https://github.com/satoren/y-phoenix-channel)
