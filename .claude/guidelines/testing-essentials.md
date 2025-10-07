# Testing Essentials: Avoiding Over-Testing

## Overview

These guidelines ensure maintainable, readable tests that focus on behavior rather than exhaustive coverage. **The #1 priority is avoiding brain-numbing micro-tests.**

**Testing Philosophy:**
- Write tests that focus on behavior, not implementation details
- Keep tests fast, focused, and independent
- Prioritize readability and maintainability over cleverness
- Test from the user's perspective when possible
- **Group related assertions - avoid micro-testing individual properties**

## ⚠️ AVOIDING OVER-TESTING: The #1 Priority

**The Problem:** It's easy to write tests that are so granular they become exhausting to read and maintain. A 700-line test file with dozens of micro-tests testing individual properties is worse than a 200-line file with well-organized behavioral tests.

### Red Flags You're Over-Testing

🚫 **Test file is > 500 lines** - Time to consolidate
🚫 **One test per property/assertion** - Group related assertions
🚫 **Repeating setup code extensively** - Extract helpers or use fixtures
🚫 **Tests that just verify framework behavior** - Focus on your logic
🚫 **Tests reading like a spec sheet** - Test behaviors, not structure

### The Fix: Group Related Assertions

**❌ Brain-Numbing Micro-Tests** (from actual codebase):
```typescript
describe("state management", () => {
  describe("loading state", () => {
    test("setLoading updates loading state and notifies subscribers", () => {
      const store = createAdaptorStore();
      let notificationCount = 0;
      store.subscribe(() => { notificationCount++; });

      store.setLoading(true);
      expect(store.getSnapshot().isLoading).toBe(true);

      store.setLoading(false);
      expect(store.getSnapshot().isLoading).toBe(false);
      expect(notificationCount).toBe(2);
    });
  });

  describe("error state", () => {
    test("setError updates error state and sets loading to false", () => {
      const store = createAdaptorStore();
      store.setLoading(true);

      store.setError("Test error");
      expect(store.getSnapshot().error).toBe("Test error");
      expect(store.getSnapshot().isLoading).toBe(false);
    });

    test("clearError removes error state", () => {
      const store = createAdaptorStore();
      store.setError("Test error");

      store.clearError();
      expect(store.getSnapshot().error).toBeNull();
    });
  });

  describe("adaptors state", () => {
    test("setAdaptors updates adaptors list and metadata", () => {
      const store = createAdaptorStore();
      store.setAdaptors(mockAdaptorsList);

      const state = store.getSnapshot();
      expect(state.adaptors).toEqual(mockAdaptorsList);
      expect(state.error).toBeNull();
      expect(state.lastUpdated).toBeGreaterThan(0);
    });
  });
});
```
**Result:** 40+ lines for basic state management tests

**✅ Clear, Grouped Tests:**
```typescript
describe("state management", () => {
  test("manages loading, error, and data state correctly", () => {
    const store = createAdaptorStore();
    let notificationCount = 0;
    store.subscribe(() => { notificationCount++; });

    // Loading state
    store.setLoading(true);
    expect(store.getSnapshot().isLoading).toBe(true);
    expect(notificationCount).toBe(1);

    // Error clears loading
    store.setError("Network error");
    const errorState = store.getSnapshot();
    expect(errorState.error).toBe("Network error");
    expect(errorState.isLoading).toBe(false);
    expect(notificationCount).toBe(2);

    // Clear error
    store.clearError();
    expect(store.getSnapshot().error).toBeNull();
    expect(notificationCount).toBe(3);

    // Set data updates state and metadata
    store.setAdaptors(mockAdaptorsList);
    const finalState = store.getSnapshot();
    expect(finalState.adaptors).toEqual(mockAdaptorsList);
    expect(finalState.error).toBeNull();
    expect(finalState.lastUpdated).toBeGreaterThan(0);
    expect(notificationCount).toBe(4);
  });
});
```
**Result:** ~25 lines, same coverage, much clearer workflow

### When to Separate vs Group Tests

**✅ Separate tests when:**
- Testing different user workflows (e.g., "connect to channel" vs "handle disconnect")
- Different setup requirements (e.g., "with existing data" vs "empty state")
- Testing success vs error cases (e.g., "successful response" vs "network error")
- Async vs sync behavior

**✅ Group assertions when:**
- Testing multiple properties of the same operation
- Verifying state transitions (before → action → after)
- Related side effects (e.g., "setError clears loading AND sets error message")
- Testing a complete workflow

### Real Example: From 100 lines → 30 lines

**❌ Before (exhausting):**
```typescript
test("getSnapshot returns empty adaptors array", () => {
  expect(store.getSnapshot().adaptors).toEqual([]);
});

test("getSnapshot returns isLoading as false", () => {
  expect(store.getSnapshot().isLoading).toBe(false);
});

test("getSnapshot returns error as null", () => {
  expect(store.getSnapshot().error).toBe(null);
});

test("getSnapshot returns lastUpdated as null", () => {
  expect(store.getSnapshot().lastUpdated).toBe(null);
});
```

**✅ After (clear):**
```typescript
test("initializes with default state", () => {
  const state = store.getSnapshot();
  expect(state).toEqual({
    adaptors: [],
    isLoading: false,
    error: null,
    lastUpdated: null,
  });
});
```

### Elixir/ExUnit Pattern

**❌ Over-tested:**
```elixir
test "job insert operation adds job to YDoc" do
  # ... setup ...
  assert Yex.Array.length(jobs_array) == 8
end

test "job insert operation sets correct job name" do
  # ... setup ...
  assert new_job_data["name"] == "New Test Job"
end

test "job insert operation sets correct job body" do
  # ... setup ...
  assert new_job_data["body"] == "console.log('new job');"
end
```

**✅ Grouped:**
```elixir
test "job insert operation updates YDoc with complete job data" do
  # ... setup ...

  # Assert job was added
  assert Yex.Array.length(jobs_array) == 8

  # Assert job data is complete using pattern matching
  assert %{
    "name" => "New Test Job",
    "body" => "console.log('new job');",
    "adaptor" => "@openfn/language-http@latest"
  } = new_job_data
end
```

### Maximum Test File Sizes

**Target limits:**
- Simple module: **< 200 lines**
- Complex store/context: **< 300 lines**
- Integration/supervisor tests: **< 400 lines**
- **Red flag:** > 500 lines means you're over-testing

If you hit these limits, you're probably:
1. Testing framework features instead of your logic
2. Breaking tests down too granularly
3. Not using test helpers/fixtures effectively
4. Testing implementation details instead of behavior

### Quick Decision Tree

```
Is this testing a single operation?
  → YES: Can you group assertions?
    → YES: Group them in one test
    → NO: Is the setup identical?
      → YES: Still consider grouping
      → NO: Separate tests OK

Is this testing user-facing behavior?
  → YES: Write the test
  → NO: Skip it (probably testing framework/library code)

Will this test catch a real bug?
  → YES: Write the test
  → NO: Skip it (probably testing trivial getters/setters)
```

## Test Structure and Organization

### File Organization

```
assets/test/
  collaborative-editor/
    stores/
      createSessionStore.test.ts
      createAdaptorStore.test.ts
    hooks/
      useSession.test.ts
    components/
      SessionProvider.test.tsx
    __helpers__/
      storeHelpers.ts
      testUtils.ts
    __fixtures__/
      adaptorData.ts
      sessionData.ts
    mocks/
      phoenixSocket.ts
      phoenixChannel.ts
```

### Test Structure Pattern

**✅ DO: Use Arrange-Act-Assert (AAA) Pattern**

```typescript
test('setError updates error state and clears loading', () => {
  // Arrange
  const store = createAdaptorStore();
  store.setLoading(true);
  const errorMessage = 'Test error message';

  // Act
  store.setError(errorMessage);

  // Assert
  const state = store.getSnapshot();
  expect(state.error).toBe(errorMessage);
  expect(state.isLoading).toBe(false);
});
```

### Grouping Tests with Describe Blocks

**✅ DO: Use describe blocks for logical grouping**

```typescript
describe('createSessionStore', () => {
  describe('initialization', () => {
    test('returns initial state with null values', () => {
      const store = createSessionStore();
      const state = store.getSnapshot();

      expect(state.ydoc).toBe(null);
      expect(state.provider).toBe(null);
      expect(state.isConnected).toBe(false);
    });
  });

  describe('subscriptions', () => {
    test('notifies subscribers on state change', () => {
      // Test subscription
    });
  });

  describe('cleanup', () => {
    test('destroy cleans up all resources', () => {
      // Test cleanup
    });
  });
});
```

## Test Naming Conventions

**✅ DO: Use descriptive, complete sentence test names**

```typescript
test('throws error when used outside SessionProvider', () => {});
test('updates adaptors list and clears loading state', () => {});
test('handles null userData gracefully', () => {});
test('maintains referential stability across state changes', () => {});
```

**❌ DON'T: Use vague or abbreviated names**

```typescript
test('it works', () => {});
test('test1', () => {});
test('error', () => {});
test('sess init', () => {});
```

## Setup and Teardown

### Using beforeEach and afterEach

**✅ DO: Extract common setup to beforeEach**

```typescript
describe('createAdaptorStore', () => {
  let store: AdaptorStoreInstance;

  beforeEach(() => {
    store = createAdaptorStore();
  });

  afterEach(() => {
    store = null;
  });

  test('initializes with empty adaptors', () => {
    expect(store.getSnapshot().adaptors).toEqual([]);
  });
});
```

### Factory Functions for Complex Setup

**✅ DO: Create factory functions for reusable setup**

```typescript
// __helpers__/storeHelpers.ts
export function setupAdaptorStoreTest() {
  const store = createAdaptorStore();
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  mockChannel.push = createMockPushWithResponse('ok', { adaptors: [] });

  return {
    store,
    mockChannel,
    mockProvider,
    cleanup: () => {
      // Cleanup logic
    },
  };
}

// Usage in tests
test('requests adaptors successfully', async () => {
  const { store, mockChannel, cleanup } = setupAdaptorStoreTest();

  try {
    await store.requestAdaptors();
    expect(store.getSnapshot().adaptors).toBeDefined();
  } finally {
    cleanup();
  }
});
```

## Async Testing Best Practices

### Handling Async Operations

**✅ DO: Use async/await properly**

```typescript
test('requestAdaptors handles successful response', async () => {
  const { store, mockChannel } = setupAdaptorStoreTest();

  mockChannel.push = (event: string) => {
    return {
      receive: (status: string, callback: (response?: unknown) => void) => {
        if (status === 'ok') {
          setTimeout(() => callback({ adaptors: mockAdaptorsList }), 0);
        }
        return this;
      },
    };
  };

  store._connectChannel(mockProvider);
  await store.requestAdaptors();

  const state = store.getSnapshot();
  expect(state.adaptors).toEqual(mockAdaptorsList);
  expect(state.isLoading).toBe(false);
});
```

**❌ DON'T: Use arbitrary timeouts**

```typescript
test('bad async test', async () => {
  store.requestAdaptors();

  // Bad - arbitrary wait
  await new Promise(resolve => setTimeout(resolve, 100));

  expect(store.getSnapshot().adaptors).toBeDefined();
});
```

**❌ DON'T: Forget to await async operations**

```typescript
test('missing await', () => {
  store.requestAdaptors(); // Returns Promise, not awaited!

  // This will fail because operation hasn't completed
  expect(store.getSnapshot().adaptors).toHaveLength(3);
});
```

## Assertions and Expectations

### Writing Clear Assertions

**✅ DO: Use specific matchers**

```typescript
test('state updates correctly', () => {
  store.setAdaptors(mockAdaptorsList);
  const state = store.getSnapshot();

  // Specific matchers
  expect(state.adaptors).toHaveLength(3);
  expect(state.adaptors[0].name).toBe('@openfn/language-http');
  expect(state.error).toBeNull();
  expect(state.lastUpdated).toBeGreaterThan(0);
});
```

**✅ DO: Test error conditions**

```typescript
test('handles invalid data gracefully', async () => {
  const invalidData = { invalid: 'data' };

  mockChannel.push = createMockPushWithResponse('ok', {
    adaptors: [invalidData]
  });

  await store.requestAdaptors();

  const state = store.getSnapshot();
  expect(state.adaptors).toEqual([]);
  expect(state.error).toContain('Invalid adaptors data');
});
```

**❌ DON'T: Make vague assertions**

```typescript
test('vague test', () => {
  store.setAdaptors(mockAdaptorsList);
  const state = store.getSnapshot();

  // Too vague
  expect(state).toBeTruthy();
  expect(state.adaptors).toBeDefined();
  expect(state.adaptors.length).toBeGreaterThan(0);
});
```

**❌ DON'T: Assert implementation details**

```typescript
test('bad implementation test', () => {
  const store = createAdaptorStore();

  // Bad - testing internal state variable name
  expect(store._internalState).toBeDefined();

  // Good - testing public API
  expect(store.getSnapshot()).toBeDefined();
});
```

## Common Pitfalls to Avoid

### 1. Testing Implementation Details

**❌ DON'T:**
```typescript
test('uses Map internally', () => {
  const store = createAdaptorStore();
  expect(store._internalMap instanceof Map).toBe(true);
});
```

**✅ DO:**
```typescript
test('findAdaptorByName returns correct adaptor', () => {
  store.setAdaptors(mockAdaptorsList);
  const adaptor = store.findAdaptorByName('@openfn/language-http');
  expect(adaptor?.name).toBe('@openfn/language-http');
});
```

### 2. Flaky Async Tests

**❌ DON'T:**
```typescript
test('flaky test', async () => {
  triggerAsyncUpdate();
  await new Promise(resolve => setTimeout(resolve, 10)); // Might not be enough
  expect(store.getSnapshot().isComplete).toBe(true);
});
```

**✅ DO:**
```typescript
test('reliable test', async () => {
  triggerAsyncUpdate();
  await waitFor(() => {
    expect(store.getSnapshot().isComplete).toBe(true);
  }, { timeout: 1000 });
});
```

### 3. Over-Mocking

**❌ DON'T:**
```typescript
vi.mock('../../js/collaborative-editor/stores/createAdaptorStore');
vi.mock('yjs');
vi.mock('y-phoenix-channel');
// Mocking everything - might as well not test
```

**✅ DO:**
```typescript
// Only mock external dependencies
const mockChannel = createMockPhoenixChannel();

// Use real implementations of your code
const store = createAdaptorStore();
```

## Test Coverage Guidelines

### Strategic Test Coverage

**Test Layers:**
- **Unit Tests (70%)**: Pure functions, store logic, selectors - fast and numerous
- **Integration Tests (20%)**: Store + channel interactions - moderate speed
- **E2E Tests (10%)**: Full user flows - slow but comprehensive

**✅ DO: Prioritize high-value tests**

```typescript
// High value - tests core business logic
test('session store maintains connection state correctly', () => {});

// High value - tests error handling
test('adaptor store handles network failures gracefully', () => {});

// Low value - tests trivial getter
test('getName returns name property', () => {}); // Skip this
```

**✅ DO: Test edge cases and boundaries**

```typescript
describe('edge cases', () => {
  test('handles null userData', () => {
    store.initializeSession(mockSocket, 'room', null);
    expect(store.getSnapshot().userData).toBeNull();
  });

  test('handles empty adaptors array', () => {
    store.setAdaptors([]);
    expect(store.getSnapshot().adaptors).toEqual([]);
  });
});
```

**❌ DON'T: Test framework features**

```typescript
// Bad - testing Zustand, not your code
test('store updates', () => {
  const store = createAdaptorStore();
  store.setLoading(true);
  expect(store.getSnapshot().isLoading).toBe(true);
  // This is just testing that Zustand works
});

// Good - testing your business logic
test('setError clears loading state', () => {
  store.setLoading(true);
  store.setError('Network error');
  expect(store.getSnapshot().isLoading).toBe(false);
  // This tests your specific business rule
});
```

## Running Tests

### Command Reference

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Run tests with coverage
npm run test:coverage

# Run specific test file
npm test -- useSession.test.ts

# Run test at specific line
npm test -- useSession.test.ts:45

# Run only tests matching pattern
npm test -- --grep "SessionStore"
```

### Coverage Thresholds

Maintain these minimum coverage targets:

```json
{
  "test": {
    "coverage": {
      "lines": 80,
      "functions": 80,
      "branches": 75,
      "statements": 80
    }
  }
}
```

**Focus on:**
- Critical business logic: 90%+ coverage
- Store implementations: 85%+ coverage
- Utility functions: 80%+ coverage
- Type definitions: Not required

## Summary Checklist

Before submitting tests, verify:

- [ ] **File is under target size** (< 200-400 lines depending on complexity)
- [ ] **Related assertions are grouped** - not one test per property
- [ ] Tests follow AAA (Arrange-Act-Assert) pattern
- [ ] Test names are descriptive and complete sentences
- [ ] Tests are independent and can run in any order
- [ ] Async operations use proper await/waitFor patterns
- [ ] No arbitrary timeouts (use waitFor instead)
- [ ] Common setup extracted to beforeEach or factories
- [ ] Mocks are cleaned up after each test
- [ ] Tests focus on behavior, not implementation
- [ ] Edge cases and error conditions are tested
- [ ] Tests run fast (< 100ms for unit tests)
- [ ] describe blocks group related tests logically

## Additional Resources

For specific patterns, see:
- **React patterns**: `.claude/guidelines/testing/react-patterns.md` - act(), hooks, RTL
- **Vitest advanced**: `.claude/guidelines/testing/vitest-advanced.md` - fixtures, performance
- **Lightning-specific**: `.claude/guidelines/testing/collaborative-editor.md` - Yjs, Phoenix channels

---

**Remember:** Good tests are readable, maintainable, and give you confidence to refactor. A 200-line test file with grouped assertions is better than a 700-line file with micro-tests.
