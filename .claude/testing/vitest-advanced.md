# Vitest Advanced Features

Advanced Vitest 3.x features for fixtures, performance optimization, and specialized testing patterns. Use these when optimizing or tackling complex scenarios.

## Vitest 3.x Features (We're on 3.2.4)

### Key Features to Leverage

**AbortSignal Support (3.2+):**
```typescript
test('cleanup on abort', async ({ task }) => {
  const controller = new AbortController();

  task.signal.addEventListener('abort', () => {
    // Cleanup resources
    controller.abort();
  });

  // Your test logic
});
```

**Fixture Scoping (3.2+):**
```typescript
// Shared fixture across all tests in file
const myTest = test.extend({
  store: async ({}, use) => {
    const store = createAdaptorStore();
    await use(store);
    store.destroy();
  },
}, { scope: 'file' });

myTest('uses shared store', ({ store }) => {
  expect(store).toBeDefined();
});
```

**Watch Trigger Patterns (3.2+):**
```json
{
  "test": {
    "watchTriggerPatterns": [
      "**/*.ts",
      "!**/node_modules/**"
    ]
  }
}
```

**Conditional Skip (3.1+):**
```typescript
test.skip(condition, 'skips when condition is true', () => {
  // Test logic
});
```

**Filename and Line Number Testing (3.0+):**
```bash
# Run specific test at line number
npm test -- collaborative-editor/useSession.test.ts:45
```

## Test Fixtures with Vitest 3.2

### What Are Fixtures?

Fixtures are a way to set up and tear down test dependencies automatically. They're especially useful when you have complex setup that's shared across tests.

**✅ DO: Use Vitest 3.2 fixtures for shared resources**

```typescript
const myTest = test.extend({
  store: async ({}, use) => {
    const store = createSessionStore();
    await use(store);
    store.destroy();
  },
  mockSocket: async ({}, use) => {
    const socket = createMockSocket();
    await use(socket);
  },
});

myTest('uses fixtures', ({ store, mockSocket }) => {
  store.initializeSession(mockSocket, 'test:room', null);
  expect(store.isReady()).toBe(true);
});
```

### Define Reusable Test Fixtures

**Define fixtures once:**
```typescript
// Define fixtures once
const myTest = test.extend({
  // Automatic store setup and cleanup
  store: async ({}, use) => {
    const store = createAdaptorStore();
    await use(store);
    // Cleanup happens automatically
  },

  // Fixture with scope options
  sharedChannel: async ({}, use) => {
    const channel = createMockPhoenixChannel();
    await use(channel);
  },
});

// Use fixtures in tests
myTest('uses fixtures automatically', async ({ store, sharedChannel }) => {
  store._connectChannel(sharedChannel);
  await store.requestAdaptors();
  expect(store.getSnapshot().adaptors).toBeDefined();
});

// File-scoped fixtures (3.2+)
const fileTest = test.extend(
  {
    expensiveSetup: async ({}, use) => {
      const data = await expensiveOperation();
      await use(data);
    },
  },
  { scope: 'file' } // Shared across all tests in file
);
```

### When to Use Fixtures vs beforeEach

**Use fixtures when:**
- You need automatic cleanup
- Setup is complex and reusable
- Different tests need different combinations of setup
- You want type-safe test dependencies

**Use beforeEach when:**
- Simple setup that applies to all tests in describe
- Setup is straightforward and doesn't need parameterization
- You don't need per-test cleanup logic

## Performance Optimization

### Test Performance

**✅ DO: Keep unit tests fast (< 100ms each)**

```typescript
test('fast unit test', () => {
  const result = processAdaptorName('@openfn/language-http');
  expect(result).toBe('language-http');
}); // Takes < 1ms
```

**✅ DO: Use concurrent tests when independent**

```typescript
describe.concurrent('independent store tests', () => {
  test('creates store 1', () => {
    const store1 = createAdaptorStore();
    expect(store1).toBeDefined();
  });

  test('creates store 2', () => {
    const store2 = createSessionStore();
    expect(store2).toBeDefined();
  });

  // These can run in parallel
});
```

**✅ DO: Skip slow tests in watch mode**

```typescript
test.skipIf(process.env.WATCH_MODE)('slow integration test', async () => {
  // Expensive operation
  await setupRealDatabase();
  await runMigrations();
  // Test logic
});
```

**❌ DON'T: Create slow unit tests**

```typescript
test('slow test', async () => {
  // Bad - unnecessary delays in unit tests
  await new Promise(resolve => setTimeout(resolve, 5000));
  expect(true).toBe(true);
});
```

### Configuration Options for Faster Tests

**Test Isolation:**
```typescript
// vitest.config.ts
export default defineConfig({
  test: {
    // Disable isolation for tests without side effects (faster)
    isolate: false,
    // Note: Only use this if your tests don't have shared state issues
  },
});
```

**Pool Selection:**
```typescript
// vitest.config.ts
export default defineConfig({
  test: {
    // Use threads pool for faster execution (default is 'forks')
    pool: 'threads',
    // Note: 'threads' is faster but 'forks' is more compatible
  },
});
```

**File Parallelism:**
```typescript
// vitest.config.ts
export default defineConfig({
  test: {
    // Disable file parallelism for faster startup
    fileParallelism: false,
    // Useful for projects with many small test files
  },
});
```

**CLI Options:**
```bash
# Run tests with optimizations
npm test -- --no-isolate --pool=threads --no-file-parallelism

# Run tests with sharding (for CI/CD)
npm test -- --shard=1/4  # Run 1st quarter of tests
npm test -- --shard=2/4  # Run 2nd quarter of tests
```

### When to Use Performance Optimizations

**✅ DO: Use `--no-isolate` when:**
- Tests don't modify global state
- Tests are purely functional
- Tests don't have side effects
- You've verified tests remain independent

**✅ DO: Use `--pool=threads` when:**
- You need faster test execution
- Your environment supports worker threads
- Tests don't rely on fork-specific behavior

**✅ DO: Use sharding when:**
- Running tests in CI/CD across multiple machines
- You have high CPU-count machines
- Test suite is very large (1000+ tests)

**❌ DON'T: Optimize prematurely:**
- Start with default settings
- Profile your tests first to identify bottlenecks
- Only optimize if tests are actually slow (> 30s total)

## Test Context Hooks

### onTestFinished - Cleanup per test

```typescript
test('cleanup specific resources', async () => {
  const resource = await createResource();

  onTestFinished(async () => {
    // Cleanup specific to this test
    await resource.cleanup();
  });

  // Test logic
  await resource.doSomething();
  expect(resource.isActive).toBe(true);
  // Cleanup happens automatically after test
});
```

### onTestFailed - Handle test failures

```typescript
test('capture debug info on failure', async () => {
  const store = createAdaptorStore();

  onTestFailed((result) => {
    // Log state for debugging
    console.log('Test failed with state:', store.getSnapshot());
    console.log('Errors:', result.errors);
  });

  // Test logic that might fail
  await store.requestAdaptors();
  expect(store.getSnapshot().adaptors).toHaveLength(3);
});
```

## Conditional Test Execution (3.1+)

```typescript
// Skip based on environment
test.skipIf(process.env.CI)('local only test', () => {
  // Only runs in local development
});

test.runIf(process.env.ENABLE_INTEGRATION_TESTS)(
  'integration test',
  async () => {
    // Only runs when flag is set
  }
);

// Dynamic skip condition
const isSlowEnvironment = checkEnvironmentSpeed();
test.skipIf(isSlowEnvironment)('fast test', () => {
  // Skipped on slow environments
});
```

## Benchmarking with Vitest

```typescript
import { bench, describe } from 'vitest';

describe('performance tests', () => {
  bench('selector performance', () => {
    const store = createAdaptorStore();
    store.setAdaptors(mockAdaptorsList);

    for (let i = 0; i < 1000; i++) {
      store.findAdaptorByName('@openfn/language-http');
    }
  });

  bench('direct access performance', () => {
    const adaptors = mockAdaptorsList;

    for (let i = 0; i < 1000; i++) {
      adaptors.find((a) => a.name === '@openfn/language-http');
    }
  });
});
```

## Test Filtering by Location (3.0+)

```bash
# Run specific test by line number
npm test -- useSession.test.ts:45

# Run tests in range
npm test -- useSession.test.ts:45-100

# Combine with watch mode
npm test -- --watch useSession.test.ts:45
```

## Type Testing (Vitest 3.x)

```typescript
import { expectTypeOf } from 'vitest';

test('type assertions', () => {
  const store = createAdaptorStore();

  // Assert types at compile and runtime
  expectTypeOf(store.getSnapshot).toBeFunction();
  expectTypeOf(store.getSnapshot()).toMatchTypeOf<AdaptorState>();

  // Assert parameter types
  expectTypeOf(store.setAdaptors).parameter(0).toMatchTypeOf<Adaptor[]>();

  // Assert return types
  expectTypeOf(store.findAdaptorByName).returns.toMatchTypeOf<
    Adaptor | null
  >();
});
```

## Test.each for Parameterized Tests

**✅ DO: Use test.each for multiple scenarios**

```typescript
test.each([
  { name: '@openfn/language-http', expected: 'language-http' },
  { name: '@openfn/language-dhis2', expected: 'language-dhis2' },
  { name: '@openfn/language-salesforce', expected: 'language-salesforce' },
])('extracts adaptor name from $name', ({ name, expected }) => {
  expect(extractAdaptorName(name)).toBe(expected);
});

// Table syntax (alternative)
test.each`
  version      | isValid
  ${'1.0.0'}   | ${true}
  ${'1.0'}     | ${false}
  ${'invalid'} | ${false}
`('validates version $version as $isValid', ({ version, isValid }) => {
  expect(isValidVersion(version)).toBe(isValid);
});
```

## Mocking Strategies

### Phoenix Channels and Sockets

**✅ DO: Create reusable mock factories**

```typescript
// mocks/phoenixChannel.ts
export function createMockPhoenixChannel(topic = 'test:channel') {
  const eventHandlers = new Map();

  return {
    topic,
    on(event: string, handler: (msg: unknown) => void) {
      if (!eventHandlers.has(event)) {
        eventHandlers.set(event, new Set());
      }
      eventHandlers.get(event).add(handler);
    },
    off(event: string, handler: (msg: unknown) => void) {
      eventHandlers.get(event)?.delete(handler);
    },
    push(event: string, payload: unknown) {
      return {
        receive(status: string, callback: (resp?: unknown) => void) {
          if (status === 'ok') {
            setTimeout(() => callback({ status: 'ok' }), 0);
          }
          return this;
        },
      };
    },
    // Test helper for simulating events
    _test: {
      emit(event: string, message: unknown) {
        eventHandlers.get(event)?.forEach(handler => handler(message));
      },
    },
  };
}
```

**✅ DO: Mock at the right level**

```typescript
// Good - mock the external dependency (Phoenix channel)
const mockChannel = createMockPhoenixChannel();

// Good - use real store logic
const store = createAdaptorStore();
store._connectChannel(mockChannel);
```

**❌ DON'T: Over-mock internal logic**

```typescript
// Bad - mocking the thing you're testing
vi.mock('../../js/collaborative-editor/stores/createAdaptorStore', () => ({
  createAdaptorStore: vi.fn(() => ({
    getSnapshot: () => ({ adaptors: [] }),
    // Mocking everything defeats the purpose
  })),
}));
```

### Spying on Functions

**✅ DO: Use vi.spyOn for tracking calls**

```typescript
test('destroy calls cleanup methods', () => {
  const store = createSessionStore();
  const ydoc = store.initializeYDoc();

  const destroySpy = vi.spyOn(ydoc, 'destroy');

  store.destroy();

  expect(destroySpy).toHaveBeenCalledTimes(1);
  destroySpy.mockRestore();
});
```

**✅ DO: Clean up mocks after tests**

```typescript
afterEach(() => {
  vi.clearAllMocks();
  vi.restoreAllMocks();
});
```

## Test Data and Fixtures

### Creating Test Fixtures

**✅ DO: Use fixture files for complex data**

```typescript
// fixtures/adaptorData.ts
export const mockAdaptor: Adaptor = {
  name: '@openfn/language-http',
  versions: [
    { version: '2.1.0' },
    { version: '2.0.5' },
  ],
  repo: 'https://github.com/OpenFn/adaptors/tree/main/packages/http',
  latest: '2.1.0',
};

export const mockAdaptorsList: Adaptor[] = [
  mockAdaptor,
  mockAdaptorDhis2,
  mockAdaptorSalesforce,
];
```

**✅ DO: Use builder pattern for flexible test data**

```typescript
// fixtures/builders.ts
export class AdaptorBuilder {
  private adaptor: Partial<Adaptor> = {};

  withName(name: string) {
    this.adaptor.name = name;
    return this;
  }

  withVersions(...versions: string[]) {
    this.adaptor.versions = versions.map(v => ({ version: v }));
    this.adaptor.latest = versions[0];
    return this;
  }

  build(): Adaptor {
    return {
      name: this.adaptor.name ?? '@openfn/language-test',
      versions: this.adaptor.versions ?? [{ version: '1.0.0' }],
      repo: this.adaptor.repo ?? 'https://github.com/test',
      latest: this.adaptor.latest ?? '1.0.0',
    };
  }
}

// Usage
test('handles custom adaptor', () => {
  const adaptor = new AdaptorBuilder()
    .withName('@openfn/language-custom')
    .withVersions('3.0.0', '2.9.0', '2.8.0')
    .build();

  store.setAdaptors([adaptor]);
  expect(store.findAdaptorByName('@openfn/language-custom')).toBe(adaptor);
});
```

**✅ DO: Create minimal test data**

```typescript
test('processes adaptor name', () => {
  const adaptor = {
    name: '@openfn/language-http',
    versions: [{ version: '1.0.0' }],
    latest: '1.0.0',
    repo: 'https://github.com/test',
  };

  // Only includes what's needed for the test
  expect(extractAdaptorName(adaptor)).toBe('language-http');
});
```

**❌ DON'T: Create test data inline when it's complex**

```typescript
test('bad test data', () => {
  const adaptors = [
    {
      name: '@openfn/language-http',
      versions: [
        { version: '2.1.0' },
        { version: '2.0.5' },
        { version: '2.0.0' },
        // ... many more fields
      ],
      repo: 'https://github.com/...',
      latest: '2.1.0',
    },
    // ... many more adaptors inline
  ];

  // Test logic gets lost in data setup
});
```

## Isolating Tests

**✅ DO: Ensure test independence**

```typescript
describe('isolated tests', () => {
  let store: AdaptorStoreInstance;

  beforeEach(() => {
    store = createAdaptorStore(); // Fresh store each test
  });

  test('test 1', () => {
    store.setLoading(true);
    expect(store.getSnapshot().isLoading).toBe(true);
  });

  test('test 2', () => {
    // Clean state, not affected by test 1
    expect(store.getSnapshot().isLoading).toBe(false);
  });
});
```

**❌ DON'T: Share mutable state between tests**

```typescript
// Bad - shared state across tests
const sharedStore = createAdaptorStore();

test('test 1', () => {
  sharedStore.setLoading(true);
  expect(sharedStore.getSnapshot().isLoading).toBe(true);
});

test('test 2', () => {
  // Fails because test 1 modified the shared store
  expect(sharedStore.getSnapshot().isLoading).toBe(false);
});
```

## Additional Resources

- [Vitest Documentation](https://vitest.dev/)
- [Vitest 3.2 Release Notes](https://vitest.dev/blog/vitest-3-2.html)
- [Effective Snapshot Testing](https://kentcdodds.com/blog/effective-snapshot-testing)
