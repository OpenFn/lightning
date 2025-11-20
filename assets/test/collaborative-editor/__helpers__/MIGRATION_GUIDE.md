# Migration Guide: Using Test Helpers

This guide shows how to migrate existing test files to use the new helper
functions.

## Before and After Examples

### Example 1: Adaptor Store Test

**Before** (in createAdaptorStore.test.ts):

```typescript
test('requestAdaptors processes valid data correctly via channel', async () => {
  const store = createAdaptorStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);
  let notificationCount = 0;

  store.subscribe(() => {
    notificationCount++;
  });

  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === 'ok') {
          setTimeout(() => {
            callback({ adaptors: mockAdaptorsList });
          }, 0);
        } else if (status === 'error') {
          setTimeout(() => {
            callback({ reason: 'Error' });
          }, 0);
        } else if (status === 'timeout') {
          setTimeout(() => {
            callback();
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  store._connectChannel(mockProvider);
  await store.requestAdaptors();

  const state = store.getSnapshot();
  expect(state.adaptors).toEqual(mockAdaptorsList);
});
```

**After** (using helpers):

```typescript
import {
  setupAdaptorStoreTest,
  createMockPushWithResponse,
} from './__helpers__';

test('requestAdaptors processes valid data correctly via channel', async () => {
  const { store, mockChannel, cleanup } = setupAdaptorStoreTest();
  let notificationCount = 0;

  store.subscribe(() => {
    notificationCount++;
  });

  mockChannel.push = () =>
    createMockPushWithResponse('ok', { adaptors: mockAdaptorsList });

  await store.requestAdaptors();

  const state = store.getSnapshot();
  expect(state.adaptors).toEqual(mockAdaptorsList);

  cleanup();
});
```

**Benefits:**

- 20 fewer lines of code
- No manual channel provider setup
- Automatic cleanup
- Clearer test intent

### Example 2: Session Context Store Test

**Before** (in createSessionContextStore.test.ts):

```typescript
test('requestSessionContext processes valid data correctly via channel', async () => {
  const store = createSessionContextStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);
  let notificationCount = 0;

  store.subscribe(() => {
    notificationCount++;
  });

  mockChannel.push = (_event: string, _payload: unknown) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === 'ok') {
          setTimeout(() => {
            callback(mockSessionContextResponse);
          }, 0);
        } else if (status === 'error') {
          setTimeout(() => {
            callback({ reason: 'Error' });
          }, 0);
        } else if (status === 'timeout') {
          setTimeout(() => {
            callback();
          }, 0);
        }
        return {
          receive: () => {
            return { receive: () => ({ receive: () => ({}) }) };
          },
        };
      },
    };
  };

  store._connectChannel(mockProvider);
  await store.requestSessionContext();

  const state = store.getSnapshot();
  expect(state.user).toEqual(mockUserContext);
  expect(state.project).toEqual(mockProjectContext);
  expect(state.config).toEqual(mockAppConfig);
  expect(state.isLoading).toBe(false);
  expect(state.error).toBe(null);
});
```

**After** (using helpers):

```typescript
import {
  setupSessionContextStoreTest,
  testSessionContextRequest,
} from './__helpers__';

test('requestSessionContext processes valid data correctly via channel', async () => {
  const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

  configureMockChannelForContext(mockChannel, mockSessionContextResponse);

  await testSessionContextRequest(store, {
    user: mockUserContext,
    project: mockProjectContext,
    config: mockAppConfig,
  });

  cleanup();
});
```

**Benefits:**

- 30 fewer lines of code
- Reusable channel configuration
- Built-in assertions
- Clear test structure

### Example 3: Session Store Test

**Before** (in createSessionStore.test.ts):

```typescript
function waitForState(
  store: SessionStore,
  callback: (state: SessionState) => boolean,
  timeout = 200
) {
  const stack = new Error().stack;
  return new Promise((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      const error = new Error('Timeout waiting for state');
      error.stack = stack;
      reject(error);
    }, timeout);

    const unsubscribe = store.subscribe(() => {
      try {
        const result = callback(store.getSnapshot());
        if (result) {
          unsubscribe();
          clearTimeout(timeoutId);
          resolve(result);
        }
      } catch (error) {
        reject(error);
      }
    });
  });
}

test('provider sync updates state', async () => {
  const store = createSessionStore();
  const socket = createMockSocket();

  store.initializeSession(socket, 'test:room', {
    id: 'user-1',
    name: 'Test User',
    color: '#ff0000',
  });

  await waitForState(store, state => state.isConnected);

  store.provider!.emit('sync', [true]);

  await waitForState(store, state => state.isSynced);

  expect(store.getSnapshot().isSynced).toBe(true);

  store.destroy();
});
```

**After** (using helpers):

```typescript
import {
  setupSessionStoreTest,
  waitForState,
  triggerProviderSync,
} from './__helpers__';

test('provider sync updates state', async () => {
  const { store, cleanup } = setupSessionStoreTest('test:room', {
    id: 'user-1',
    name: 'Test User',
    color: '#ff0000',
  });

  await waitForState(store, state => state.isConnected);

  triggerProviderSync(store, true);

  await waitForState(store, state => state.isSynced);

  expect(store.getSnapshot().isSynced).toBe(true);

  cleanup();
});
```

**Benefits:**

- Helper function is reusable across tests
- No need to define `waitForState` in every test file
- Cleaner provider event triggering
- Automatic cleanup

### Example 4: StoreProvider Test

**Before** (in StoreProvider.test.tsx):

```typescript
function createStores(): StoreContextValue {
  return {
    adaptorStore: createAdaptorStore(),
    credentialStore: createCredentialStore(),
    awarenessStore: createAwarenessStore(),
    workflowStore: createWorkflowStore(),
    sessionContextStore: createSessionContextStore(),
  };
}

function simulateChannelConnection(
  stores: StoreContextValue,
  sessionStore: SessionStoreInstance
): () => void {
  const session = sessionStore.getSnapshot();

  if (session.provider && session.isConnected) {
    const cleanup1 = stores.adaptorStore._connectChannel(session.provider);
    const cleanup2 = stores.credentialStore._connectChannel(session.provider);
    const cleanup3 = stores.sessionContextStore._connectChannel(
      session.provider
    );

    return () => {
      cleanup1();
      cleanup2();
      cleanup3();
    };
  }

  return () => {};
}

test('sessionContextStore connects to channel when provider is ready', async () => {
  const sessionStore = createSessionStore();
  const stores = createStores();
  const mockSocket = createMockSocket();

  sessionStore.initializeSession(
    mockSocket,
    'test:workflow',
    {
      id: 'user-1',
      name: 'Test User',
      color: '#ff0000',
    },
    { connect: true }
  );

  await waitForAsync(100);

  const cleanup = simulateChannelConnection(stores, sessionStore);

  // ... test logic

  cleanup();
  sessionStore.destroy();
});
```

**After** (using helpers):

```typescript
import { simulateStoreProviderWithConnection } from './__helpers__';

test('sessionContextStore connects to channel when provider is ready', async () => {
  const { stores, channelCleanup, cleanup } =
    await simulateStoreProviderWithConnection();

  // ... test logic

  channelCleanup();
  cleanup();
});
```

**Benefits:**

- Eliminates boilerplate setup functions
- One-line provider setup
- Consistent cleanup pattern
- Less code to maintain

### Example 5: Breadcrumb Test

**Before** (in CollaborativeEditor.test.tsx):

```typescript
function createMockProject(
  overrides: Partial<ProjectContext> = {}
): ProjectContext {
  return {
    id: 'project-123',
    name: 'Test Project',
    ...overrides,
  };
}

function selectBreadcrumbProjectData(
  projectFromStore: ProjectContext | null,
  projectIdFallback?: string,
  projectNameFallback?: string
): { projectId: string | undefined; projectName: string | undefined } {
  const projectId = projectFromStore?.id ?? projectIdFallback;
  const projectName = projectFromStore?.name ?? projectNameFallback;

  return { projectId, projectName };
}

function generateBreadcrumbStructure(
  projectId: string | undefined,
  projectName: string | undefined,
  workflowName: string
): BreadcrumbItem[] {
  return [
    {
      type: 'link',
      href: '/',
      text: 'Home',
      icon: 'hero-home-mini',
    },
    // ... more items
  ];
}

test('uses project data from store when available', () => {
  const projectFromStore = createMockProject({
    id: 'store-project-123',
    name: 'Store Project Name',
  });
  const projectIdFallback = 'fallback-project-456';
  const projectNameFallback = 'Fallback Project Name';

  const result = selectBreadcrumbProjectData(
    projectFromStore,
    projectIdFallback,
    projectNameFallback
  );

  expect(result.projectId).toBe('store-project-123');
  expect(result.projectName).toBe('Store Project Name');
});
```

**After** (using helpers):

```typescript
import {
  createMockProject,
  selectBreadcrumbProjectData,
  testStoreFirstPattern,
} from './__helpers__';

test('uses project data from store when available', () => {
  const projectFromStore = createMockProject({
    id: 'store-project-123',
    name: 'Store Project Name',
  });

  testStoreFirstPattern(
    projectFromStore,
    'fallback-project-456',
    'Fallback Project Name'
  );
});
```

**Benefits:**

- No need to duplicate helper functions
- Built-in assertion patterns
- Consistent test structure
- Easier to add new breadcrumb tests

## Migration Checklist

When migrating a test file to use helpers:

- [ ] Import helpers from `"./__helpers__"` or specific files
- [ ] Replace inline mock setup with `setup*Test()` functions
- [ ] Replace manual push configurations with `createMockPush*()` functions
- [ ] Replace manual cleanup with returned `cleanup()` functions
- [ ] Replace inline helper functions with imported helpers
- [ ] Remove duplicate helper function definitions
- [ ] Update test structure to use helper return values
- [ ] Verify all tests still pass
- [ ] Check TypeScript types are correct

## Common Patterns

### Pattern 1: Store Setup and Cleanup

```typescript
// Old
const store = createStore();
const channel = createMockPhoenixChannel();
const provider = createMockPhoenixChannelProvider(channel);
store._connectChannel(provider);
// ... test
// No cleanup!

// New
const { store, mockChannel, cleanup } = setupStoreTest();
// ... test
cleanup();
```

### Pattern 2: Channel Response Configuration

```typescript
// Old
mockChannel.push = (_event, _payload) => {
  return {
    receive: (status, callback) => {
      if (status === 'ok') {
        setTimeout(() => callback({ data }), 0);
      }
      // ... more status handling
      return { receive: () => ({ receive: () => ({}) }) };
    },
  };
};

// New
mockChannel.push = () => createMockPushWithResponse('ok', { data });
```

### Pattern 3: Wait for Async State

```typescript
// Old
function waitForState(store, callback, timeout = 200) {
  return new Promise((resolve, reject) => {
    // ... complex implementation
  });
}

// New
import { waitForState } from './__helpers__';
await waitForState(store, state => state.isConnected);
```

## Tips

1. **Start with simple tests** - Migrate simpler tests first to get familiar
   with helpers
2. **One test at a time** - Migrate incrementally and verify each test still
   passes
3. **Keep old code initially** - Comment out old code instead of deleting until
   migration is complete
4. **Run tests frequently** - Verify tests pass after each migration step
5. **Check the examples** - Refer to USAGE_EXAMPLES.md for patterns
6. **Use TypeScript** - Let the type system guide you to correct usage

## Need Help?

- Check `README.md` for overview of all helpers
- Check `USAGE_EXAMPLES.md` for detailed examples
- Look at existing helper JSDoc comments for usage instructions
- Check the helper source code for implementation details
