# Test Helpers

This directory contains reusable test helper functions for collaborative editor
tests. These helpers consolidate common test patterns and reduce code
duplication across test files.

## File Organization

### `channelMocks.ts`

Phoenix channel mock factories for creating channel mocks with various response
patterns.

**Key Functions:**

- `createMockPhoenixChannel()` - Creates a mock Phoenix channel
- `createMockPushWithResponse()` - Creates a push handler with specific
  responses
- `configureMockChannelPush()` - Configures event-specific responses
- `createMockChannelWithError()` - Creates a channel that returns errors
- `createMockChannelWithTimeout()` - Creates a channel that times out

**Usage Example:**

```typescript
import { createMockChannelWithResponses } from './__helpers__';

const channel = createMockChannelWithResponses({
  request_adaptors: { adaptors: mockAdaptorsList },
  get_context: { user: mockUser, project: mockProject },
});
```

### `storeHelpers.ts`

Factory functions for setting up store instances with common configurations.

**Key Functions:**

- `setupAdaptorStoreTest()` - Sets up adaptor store with connected channel
- `setupSessionContextStoreTest()` - Sets up session context store
- `setupSessionStoreTest()` - Sets up session store with YDoc
- `setupMultipleStores()` - Creates multiple connected stores

**Usage Example:**

```typescript
import { setupAdaptorStoreTest } from './__helpers__';

test('adaptor store functionality', async () => {
  const { store, mockChannel, cleanup } = setupAdaptorStoreTest();

  // Configure and test
  mockChannel.push = () => createMockPushWithResponse('ok', { adaptors: [] });
  await store.requestAdaptors();

  cleanup();
});
```

### `sessionStoreHelpers.ts`

Utilities for testing session store functionality, including YDoc operations and
provider events.

**Key Functions:**

- `triggerProviderSync()` - Simulates provider sync event
- `triggerProviderStatus()` - Simulates provider status change
- `waitForState()` - Waits for specific store state
- `waitForSessionReady()` - Waits for session to be connected and synced
- `createTestYDoc()` - Creates a YDoc with test data
- `simulateRemoteUserJoin()` - Simulates remote user joining

**Usage Example:**

```typescript
import {
  setupSessionStoreTest,
  waitForSessionReady,
  triggerProviderSync,
} from './__helpers__';

test('session synchronization', async () => {
  const { store, cleanup } = setupSessionStoreTest('room:123', userData);

  await waitForSessionReady(store);
  triggerProviderSync(store, true);

  expect(store.getSnapshot().isSynced).toBe(true);

  cleanup();
});
```

### `sessionContextHelpers.ts`

Utilities for testing session context store, including channel event simulation.

**Key Functions:**

- `configureMockChannelForContext()` - Sets up channel for context requests
- `emitSessionContextEvent()` - Simulates session_context event
- `emitSessionContextUpdatedEvent()` - Simulates session_context_updated event
- `testSessionContextRequest()` - Tests request with validation
- `createMockChannelForScenario()` - Creates pre-configured channels

**Usage Example:**

```typescript
import {
  setupSessionContextStoreTest,
  emitSessionContextUpdatedEvent,
} from './__helpers__';

test('context updates', async () => {
  const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

  emitSessionContextUpdatedEvent(mockChannel, {
    user: updatedUser,
    project: updatedProject,
    config: updatedConfig,
  });

  await waitForAsync(10);
  expect(store.getSnapshot().user).toEqual(updatedUser);

  cleanup();
});
```

### `storeProviderHelpers.ts`

Utilities for testing StoreProvider context and store integration patterns.

**Key Functions:**

- `createStores()` - Creates all stores matching StoreProvider structure
- `simulateChannelConnection()` - Simulates StoreProvider's channel connection
  effect
- `simulateStoreProvider()` - Creates complete provider setup without connection
- `simulateStoreProviderWithConnection()` - Creates fully-connected provider
  setup
- `verifyAllStoresPresent()` - Verifies all stores are initialized
- `simulateProviderLifecycle()` - Simulates mount/unmount cycles

**Usage Example:**

```typescript
import { simulateStoreProviderWithConnection } from './__helpers__';

test('store integration', async () => {
  const { stores, channelCleanup, cleanup } =
    await simulateStoreProviderWithConnection();

  await stores.sessionContextStore.requestSessionContext();

  channelCleanup();
  cleanup();
});
```

### `breadcrumbHelpers.ts`

Utilities for testing breadcrumb rendering logic and the
store-first/props-fallback pattern.

**Key Functions:**

- `createMockProject()` - Creates mock project context
- `selectBreadcrumbProjectData()` - Simulates breadcrumb data selection
- `generateBreadcrumbStructure()` - Creates complete breadcrumb array
- `testStoreFirstPattern()` - Tests store-first behavior
- `createBreadcrumbScenario()` - Creates common test scenarios
- `createEdgeCaseTestData()` - Creates edge case test data

**Usage Example:**

```typescript
import {
  createMockProject,
  selectBreadcrumbProjectData,
  generateBreadcrumbStructure,
} from './__helpers__';

test('breadcrumb rendering', () => {
  const project = createMockProject({ name: 'My Project' });
  const { projectId, projectName } = selectBreadcrumbProjectData(
    project,
    'fallback-id',
    'Fallback Name'
  );

  const breadcrumbs = generateBreadcrumbStructure(
    projectId,
    projectName,
    'My Workflow'
  );

  expect(breadcrumbs[2].text).toBe('My Project');
});
```

## Design Principles

These helpers follow key testing principles:

1. **Reusability** - Common patterns are extracted into reusable functions
2. **Clarity** - Each helper has a clear, single purpose with descriptive naming
3. **Composability** - Helpers can be combined for complex test scenarios
4. **Cleanup** - All helpers that allocate resources provide cleanup functions
5. **Type Safety** - Full TypeScript support with exported types

## Import Patterns

You can import helpers individually:

```typescript
import { setupAdaptorStoreTest } from './__helpers__/storeHelpers';
```

Or use the index for multiple imports:

```typescript
import {
  setupAdaptorStoreTest,
  createMockPhoenixChannel,
  waitForAsync,
} from './__helpers__';
```

## Adding New Helpers

When adding new helpers:

1. Place them in the appropriate file based on functionality
2. Export them from `index.ts`
3. Include JSDoc comments with usage examples
4. Follow the naming convention: verb + noun (e.g., `createMock...`,
   `setup...Test`, `simulate...`)
5. Return cleanup functions for resource allocation
6. Include type exports for return types

## Testing the Helpers

These helpers themselves should be tested indirectly through their usage in
actual tests. If a helper is complex enough to warrant its own tests, consider
whether it should be part of the production code instead.
