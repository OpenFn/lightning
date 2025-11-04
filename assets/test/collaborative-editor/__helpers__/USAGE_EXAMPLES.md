# Test Helpers Usage Examples

This document provides concrete examples of how to use the test helpers in
actual test files.

## Basic Store Setup

### Adaptor Store Test

```typescript
import { describe, test, expect } from 'vitest';
import {
  setupAdaptorStoreTest,
  createMockPushWithResponse,
} from './__helpers__';
import { mockAdaptorsList } from './fixtures/adaptorData';

describe('AdaptorStore', () => {
  test('loads adaptors from channel', async () => {
    const { store, mockChannel, cleanup } = setupAdaptorStoreTest();

    // Configure channel response
    mockChannel.push = () =>
      createMockPushWithResponse('ok', { adaptors: mockAdaptorsList });

    // Test the store
    await store.requestAdaptors();

    const state = store.getSnapshot();
    expect(state.adaptors).toEqual(mockAdaptorsList);
    expect(state.isLoading).toBe(false);

    cleanup();
  });
});
```

### Session Context Store Test

```typescript
import { describe, test, expect } from 'vitest';
import {
  setupSessionContextStoreTest,
  emitSessionContextUpdatedEvent,
  waitForAsync,
} from './__helpers__';
import {
  mockUserContext,
  mockProjectContext,
  mockAppConfig,
} from './__helpers__/sessionContextFactory';

describe('SessionContextStore', () => {
  test('handles context updates', async () => {
    const { store, mockChannel, cleanup } = setupSessionContextStoreTest();

    // Simulate server event
    emitSessionContextUpdatedEvent(mockChannel, {
      user: mockUserContext,
      project: mockProjectContext,
      config: mockAppConfig,
    });

    await waitForAsync(10);

    const state = store.getSnapshot();
    expect(state.user).toEqual(mockUserContext);
    expect(state.project).toEqual(mockProjectContext);

    cleanup();
  });
});
```

## Session Store Tests

### Basic Session Setup

```typescript
import { describe, test, expect } from 'vitest';
import {
  setupSessionStoreTest,
  waitForSessionReady,
  triggerProviderSync,
} from './__helpers__';

describe('SessionStore', () => {
  test('initializes and syncs session', async () => {
    const { store, cleanup } = setupSessionStoreTest('room:123', {
      id: 'user-1',
      name: 'Test User',
      color: '#ff0000',
    });

    await waitForSessionReady(store);

    const state = store.getSnapshot();
    expect(state.isConnected).toBe(true);
    expect(state.isSynced).toBe(true);

    cleanup();
  });

  test('handles provider sync events', () => {
    const { store, cleanup } = setupSessionStoreTest();

    triggerProviderSync(store, true);

    expect(store.getSnapshot().isSynced).toBe(true);

    cleanup();
  });
});
```

### Advanced Session Testing

```typescript
import { describe, test, expect } from 'vitest';
import {
  setupSessionStoreTest,
  createTestYDoc,
  extractYDocData,
  simulateRemoteUserJoin,
} from './__helpers__';

describe('SessionStore - Collaborative Features', () => {
  test('handles remote user joining', () => {
    const { store, cleanup } = setupSessionStoreTest('room:123', {
      id: 'user-1',
      name: 'Local User',
      color: '#ff0000',
    });

    simulateRemoteUserJoin(store, 456, {
      id: 'user-2',
      name: 'Remote User',
      color: '#00ff00',
    });

    const awareness = store.getAwareness();
    expect(awareness).not.toBe(null);

    cleanup();
  });

  test('works with YDoc data', () => {
    const ydoc = createTestYDoc({ name: 'Test Workflow', version: 1 });
    const data = extractYDocData(ydoc);

    expect(data.name).toBe('Test Workflow');
    expect(data.version).toBe(1);
  });
});
```

## Store Provider Integration Tests

### Basic Integration

```typescript
import { describe, test, expect } from 'vitest';
import {
  simulateStoreProvider,
  verifyAllStoresPresent,
  verifyStoresAreIndependent,
} from './__helpers__';

describe('StoreProvider Integration', () => {
  test('creates all stores correctly', () => {
    const { stores, cleanup } = simulateStoreProvider();

    verifyAllStoresPresent(stores);
    verifyStoresAreIndependent(stores);

    cleanup();
  });
});
```

### Connected Integration

```typescript
import { describe, test, expect } from 'vitest';
import { simulateStoreProviderWithConnection } from './__helpers__';

describe('StoreProvider - Connected', () => {
  test('stores can communicate through channel', async () => {
    const { stores, channelCleanup, cleanup } =
      await simulateStoreProviderWithConnection();

    // Test that stores can make requests
    const contextPromise = stores.sessionContextStore.requestSessionContext();
    const adaptorsPromise = stores.adaptorStore.requestAdaptors();

    // Both should return promises
    expect(contextPromise).toBeInstanceOf(Promise);
    expect(adaptorsPromise).toBeInstanceOf(Promise);

    channelCleanup();
    cleanup();
  });
});
```

### Lifecycle Testing

```typescript
import { describe, test, expect } from 'vitest';
import { simulateProviderLifecycle } from './__helpers__';

describe('StoreProvider Lifecycle', () => {
  test('handles mount/unmount cycles', async () => {
    const lifecycle = simulateProviderLifecycle();

    // First mount
    const setup1 = await lifecycle.mount('room:1');
    expect(setup1.stores.sessionContextStore).toBeDefined();
    lifecycle.unmount(setup1);

    // Second mount with different room
    const setup2 = await lifecycle.mount('room:2');
    expect(setup2.stores.sessionContextStore).not.toBe(
      setup1.stores.sessionContextStore
    );
    lifecycle.unmount(setup2);

    // Cleanup any remaining
    lifecycle.unmountAll();
  });
});
```

## Breadcrumb Tests

### Basic Breadcrumb Logic

```typescript
import { describe, test, expect } from 'vitest';
import {
  createMockProject,
  selectBreadcrumbProjectData,
  generateBreadcrumbStructure,
  verifyCompleteBreadcrumbStructure,
} from './__helpers__';

describe('Breadcrumb Rendering', () => {
  test('uses store data when available', () => {
    const project = createMockProject({
      id: 'project-123',
      name: 'My Project',
    });

    const { projectId, projectName } = selectBreadcrumbProjectData(
      project,
      'fallback-id',
      'Fallback Name'
    );

    expect(projectId).toBe('project-123');
    expect(projectName).toBe('My Project');
  });

  test('generates complete breadcrumb structure', () => {
    const breadcrumbs = generateBreadcrumbStructure(
      'project-123',
      'My Project',
      'My Workflow'
    );

    verifyCompleteBreadcrumbStructure(breadcrumbs);
    expect(breadcrumbs[2].text).toBe('My Project');
    expect(breadcrumbs[4].text).toBe('My Workflow');
  });
});
```

### Scenario Testing

```typescript
import { describe, test, expect } from 'vitest';
import {
  createBreadcrumbScenario,
  selectBreadcrumbProjectData,
} from './__helpers__';

describe('Breadcrumb Scenarios', () => {
  test('initial load scenario', () => {
    const scenario = createBreadcrumbScenario('initial-load');

    const { projectId, projectName } = selectBreadcrumbProjectData(
      scenario.projectFromStore,
      scenario.projectIdFallback,
      scenario.projectNameFallback
    );

    // Should use fallback props (store not hydrated)
    expect(projectId).toBe(scenario.projectIdFallback);
    expect(projectName).toBe(scenario.projectNameFallback);
  });

  test('store hydrated scenario', () => {
    const scenario = createBreadcrumbScenario('store-hydrated');

    const { projectId, projectName } = selectBreadcrumbProjectData(
      scenario.projectFromStore,
      scenario.projectIdFallback,
      scenario.projectNameFallback
    );

    // Should use store data (not fallback)
    expect(projectId).toBe(scenario.projectFromStore!.id);
    expect(projectName).toBe(scenario.projectFromStore!.name);
  });
});
```

### Edge Case Testing

```typescript
import { describe, test, expect } from 'vitest';
import {
  createEdgeCaseTestData,
  selectBreadcrumbProjectData,
} from './__helpers__';

describe('Breadcrumb Edge Cases', () => {
  test('handles special characters', () => {
    const edgeCase = createEdgeCaseTestData('special-characters');

    const { projectName } = selectBreadcrumbProjectData(
      edgeCase.projectFromStore,
      edgeCase.fallbackId,
      edgeCase.fallbackName
    );

    expect(projectName).toContain('<>&');
  });

  test('handles very long names', () => {
    const edgeCase = createEdgeCaseTestData('very-long-name');

    const { projectName } = selectBreadcrumbProjectData(
      edgeCase.projectFromStore,
      edgeCase.fallbackId,
      edgeCase.fallbackName
    );

    expect(projectName?.length).toBe(500);
  });
});
```

## Channel Mock Patterns

### Pre-configured Responses

```typescript
import { describe, test, expect } from 'vitest';
import { createMockChannelWithResponses } from './__helpers__';
import { createSessionContextStore } from '../../js/collaborative-editor/stores/createSessionContextStore';

describe('Channel Mocks', () => {
  test('uses pre-configured responses', async () => {
    const channel = createMockChannelWithResponses({
      get_context: {
        user: { id: 'user-1', email: 'test@example.com' },
        project: { id: 'proj-1', name: 'Test' },
        config: { require_email_verification: false },
      },
    });

    const store = createSessionContextStore();
    store._connectChannel({ channel });

    await store.requestSessionContext();

    const state = store.getSnapshot();
    expect(state.user?.id).toBe('user-1');
  });
});
```

### Error Scenarios

```typescript
import { describe, test, expect } from 'vitest';
import { createMockChannelWithError } from './__helpers__';
import { createAdaptorStore } from '../../js/collaborative-editor/stores/createAdaptorStore';

describe('Error Handling', () => {
  test('handles channel errors', async () => {
    const channel = createMockChannelWithError('Server unavailable');
    const store = createAdaptorStore();

    store._connectChannel({ channel });
    await store.requestAdaptors();

    const state = store.getSnapshot();
    expect(state.error).toContain('Server unavailable');
  });
});
```

## Combining Multiple Helpers

```typescript
import { describe, test, expect } from 'vitest';
import {
  setupSessionStoreTest,
  setupSessionContextStoreTest,
  waitForAsync,
  emitSessionContextUpdatedEvent,
} from './__helpers__';
import { mockUserContext } from './__helpers__/sessionContextFactory';

describe('Complex Integration', () => {
  test('session and context stores work together', async () => {
    // Set up session store
    const sessionSetup = setupSessionStoreTest('room:123', {
      id: 'user-1',
      name: 'Test User',
      color: '#ff0000',
    });

    // Set up context store
    const contextSetup = setupSessionContextStoreTest();

    // Simulate context update
    emitSessionContextUpdatedEvent(contextSetup.mockChannel, {
      user: mockUserContext,
      project: null,
      config: { require_email_verification: false },
    });

    await waitForAsync(10);

    // Verify both stores are working
    expect(sessionSetup.store.getSnapshot().isConnected).toBe(true);
    expect(contextSetup.store.getSnapshot().user).toEqual(mockUserContext);

    // Cleanup
    contextSetup.cleanup();
    sessionSetup.cleanup();
  });
});
```

## Tips

1. **Always call cleanup functions** - This prevents memory leaks and side
   effects between tests
2. **Use waitForAsync** - Give async operations time to complete
3. **Combine helpers** - Don't be afraid to use multiple helpers in one test
4. **Check types** - TypeScript will help you use the helpers correctly
5. **Read the JSDoc** - Each helper has documentation with examples
