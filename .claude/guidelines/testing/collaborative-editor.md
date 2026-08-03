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
  const jobs = ydoc.getArray<Y.Map<string>>('jobs');
  const undoManager = new Y.UndoManager(jobs);

  const job = new Y.Map<string>();
  job.set('id', 'job1');
  job.set('name', 'Initial Name');
  jobs.push([job]);

  // Separate transaction so the UndoManager does not merge it with the insert.
  undoManager.stopCapturing();
  job.set('name', 'Updated Name');
  expect(jobs.get(0).get('name')).toBe('Updated Name');

  undoManager.undo();
  expect(jobs.get(0).get('name')).toBe('Initial Name');

  undoManager.redo();
  expect(jobs.get(0).get('name')).toBe('Updated Name');
});
```

The job has to be a `Y.Map` for the edit to be a Yjs transaction at all, and `stopCapturing()` is load-bearing: `Y.UndoManager` merges operations inside its `captureTimeout` window into one undo step, so without it the insert and the edit undo together.

## Testing Lightning-Specific Patterns

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

## Channel Mocks

`createMockPhoenixChannel` and `createMockPhoenixChannelProvider` live in `assets/test/collaborative-editor/mocks/phoenixChannel.ts`. Read that file; it is richer than any paste of it here. Beyond the Phoenix `Channel` interface the mock channel exposes a `_test` handle — `emit`, `triggerClose`, `triggerError`, `getHandlers`, `setState` — and the module also exports `waitForAsync` and `waitForCondition`.

Push responses come from `assets/test/collaborative-editor/__helpers__/channelMocks.ts` (`createMockChannelPushOk`, `createMockChannelPushError`, `createMockChannelPushTimeout`, `createMockChannelPushByEvent`, `createMockChannelPushWithHandler`), and the per-store wiring from `__helpers__/storeHelpers.ts`.
