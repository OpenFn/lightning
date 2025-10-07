# React Testing Patterns

Patterns specific to testing React components, hooks, and integration with React Testing Library.

## Understanding act() for React State Updates

### What is act() and Why Does It Exist?

`act()` from React Testing Library ensures that all React state updates, effects, and renders complete before making assertions. It wraps code that causes React state changes and flushes all pending updates synchronously.

**Why it matters:**
- React batches state updates for performance
- Without `act()`, assertions might run before updates complete
- React will warn: "An update to TestComponent inside a test was not wrapped in act(...)"
- Prevents flaky tests that depend on timing

### When to Use act()

**✅ DO: Wrap synchronous operations that trigger React state updates**

```typescript
test('wrap manual state changes in act()', async () => {
  const { result } = renderHook(() => useUser(), {
    wrapper: createWrapper(store),
  });

  // ✅ CORRECT - wrap channel emission in act()
  act(() => {
    mockChannel.emit('session_context', {
      user: mockUser,
      project: null,
      config: mockConfig,
    });
  });

  await waitFor(() => {
    expect(result.current).toEqual(mockUser);
  });
});
```

**✅ DO: Wrap store updates that trigger component re-renders**

```typescript
test('store update triggers re-render', () => {
  const { result } = renderHook(() => useAdaptors(), {
    wrapper: createWrapper(),
  });

  // ✅ CORRECT - store update affects React component
  act(() => {
    store.setAdaptors(mockAdaptorsList);
  });

  expect(result.current).toHaveLength(3);
});
```

**✅ DO: Wrap event emissions from mocked channels**

```typescript
test('Phoenix channel message updates component', async () => {
  const mockChannel = createMockPhoenixChannel();
  const mockProvider = createMockPhoenixChannelProvider(mockChannel);

  store._connectChannel(mockProvider);

  const { result } = renderHook(() => useSessionContext(), {
    wrapper: createWrapper(store),
  });

  // ✅ CORRECT - channel emission triggers React state update
  act(() => {
    mockChannel.emit('session_context', { user: mockUser, config: mockConfig });
  });

  await waitFor(() => {
    expect(result.current.user).toEqual(mockUser);
  });
});
```

### When NOT to Use act()

**❌ DON'T: Wrap RTL utilities (they already use act() internally)**

```typescript
// ❌ BAD - userEvent already wraps in act()
test('user clicks button', async () => {
  render(<Button onClick={handleClick} />);

  // Don't wrap - userEvent does this internally
  act(async () => {
    await userEvent.click(screen.getByRole('button'));
  });
});

// ✅ CORRECT - userEvent handles act() for you
test('user clicks button', async () => {
  render(<Button onClick={handleClick} />);

  await userEvent.click(screen.getByRole('button'));

  expect(handleClick).toHaveBeenCalled();
});
```

**❌ DON'T: Wrap waitFor() or findBy queries**

```typescript
// ❌ BAD - waitFor already uses act() internally
test('waits for data', async () => {
  render(<DataComponent />);

  await act(async () => {
    await waitFor(() => {
      expect(screen.getByText('Data loaded')).toBeInTheDocument();
    });
  });
});

// ✅ CORRECT - waitFor handles act() for you
test('waits for data', async () => {
  render(<DataComponent />);

  await waitFor(() => {
    expect(screen.getByText('Data loaded')).toBeInTheDocument();
  });
});
```

**❌ DON'T: Wrap renderHook or render calls**

```typescript
// ❌ BAD - render/renderHook already use act()
test('renders component', () => {
  act(() => {
    render(<MyComponent />);
  });
});

// ✅ CORRECT - no act() needed
test('renders component', () => {
  render(<MyComponent />);
  expect(screen.getByText('Hello')).toBeDefined();
});
```

### Common Scenarios Requiring act()

**Channel/Event Emissions**

When simulating external events (Phoenix channels, WebSocket messages, custom events):

```typescript
test('channel message updates state', async () => {
  const { result } = renderHook(() => useSession(), {
    wrapper: createWrapper(store),
  });

  // Channel emission triggers React state update
  act(() => {
    mockChannel.emit('presence_state', { users: mockUsers });
  });

  await waitFor(() => {
    expect(result.current.users).toEqual(mockUsers);
  });
});
```

**Direct Store Mutations**

When calling store methods that update state subscribed by React components:

```typescript
test('store mutation updates hook', () => {
  const { result } = renderHook(() => useLoading(), {
    wrapper: createWrapper(store),
  });

  act(() => {
    store.setLoading(true);
  });

  expect(result.current).toBe(true);

  act(() => {
    store.setLoading(false);
  });

  expect(result.current).toBe(false);
});
```

**Timer/Interval Triggers**

When advancing fake timers that trigger state updates:

```typescript
test('interval updates state', () => {
  vi.useFakeTimers();

  const { result } = renderHook(() => usePolling(), {
    wrapper: createWrapper(),
  });

  act(() => {
    vi.advanceTimersByTime(1000);
  });

  expect(result.current.pollCount).toBe(1);

  vi.useRealTimers();
});
```

### act() vs waitFor()

**act() is synchronous** - use for operations that complete immediately:

```typescript
// Synchronous state change
act(() => {
  store.setError('Network error');
});
expect(result.current.error).toBe('Network error');
```

**waitFor() is async** - use when waiting for eventual consistency:

```typescript
// Async operation - state updates after delay
store.requestData();

await waitFor(() => {
  expect(result.current.data).toBeDefined();
});
```

**Combine both** when triggering sync operation but waiting for async result:

```typescript
// Trigger sync, wait for async result
act(() => {
  mockChannel.emit('session_context', { user: mockUser, config: mockConfig });
});

await waitFor(() => {
  expect(result.current).toEqual(mockUser);
});
```

### Common Mistakes and Solutions

**Mistake 1: Missing act() for event emissions**

```typescript
// ❌ WRONG - warning: "update not wrapped in act()"
test('channel message', async () => {
  mockChannel.emit('session_context', { user: mockUser, config: mockConfig });

  await waitFor(() => {
    expect(result.current).toEqual(mockUser);
  });
});

// ✅ CORRECT - wrap emission in act()
test('channel message', async () => {
  act(() => {
    mockChannel.emit('session_context', { user: mockUser, config: mockConfig });
  });

  await waitFor(() => {
    expect(result.current).toEqual(mockUser);
  });
});
```

**Mistake 2: Forgetting act() when testing re-render behavior**

```typescript
// ❌ WRONG - render count won't update correctly
test('counts re-renders', () => {
  let renderCount = 0;
  const { result } = renderHook(() => {
    renderCount++;
    return useData();
  });

  const initialCount = renderCount;

  store.updateData(newData); // Missing act()!

  expect(renderCount).toBeGreaterThan(initialCount); // May fail
});

// ✅ CORRECT - wrap state change in act()
test('counts re-renders', () => {
  let renderCount = 0;
  const { result } = renderHook(() => {
    renderCount++;
    return useData();
  });

  const initialCount = renderCount;

  act(() => {
    store.updateData(newData);
  });

  expect(renderCount).toBeGreaterThan(initialCount);
});
```

**Mistake 3: Using act() with async operations incorrectly**

```typescript
// ❌ WRONG - act() can't handle async directly like this
test('async operation', async () => {
  await act(() => {
    store.requestData(); // Returns promise
  });

  expect(result.current.data).toBeDefined();
});

// ✅ CORRECT - use act() for sync trigger, waitFor for async result
test('async operation', async () => {
  act(() => {
    store.requestData();
  });

  await waitFor(() => {
    expect(result.current.data).toBeDefined();
  });
});
```

### Quick Reference

| Scenario | Use act()? | Example |
|----------|-----------|---------|
| Channel/event emission | ✅ Yes | `act(() => channel.emit(...))` |
| Store mutation | ✅ Yes | `act(() => store.setState(...))` |
| Timer advancement | ✅ Yes | `act(() => vi.advanceTimers(...))` |
| userEvent interactions | ❌ No | `await userEvent.click(...)` |
| waitFor/findBy queries | ❌ No | `await waitFor(() => ...)` |
| render/renderHook | ❌ No | `render(<Component />)` |
| Direct hook calls in test | ❌ No | Use `renderHook()` instead |

## Testing React Hooks

### Using renderHook from React Testing Library

**✅ DO: Test hooks with renderHook**

```typescript
import { renderHook, waitFor } from '@testing-library/react';

test('useAdaptors returns adaptors list', () => {
  const { result } = renderHook(() => useAdaptors(), {
    wrapper: ({ children }) => (
      <SessionProvider>{children}</SessionProvider>
    ),
  });

  expect(result.current).toEqual([]);
});
```

**✅ DO: Test hook updates with rerender**

```typescript
test('useAdaptors updates when store changes', async () => {
  const { result } = renderHook(() => useAdaptors(), {
    wrapper: SessionProviderWrapper,
  });

  // Initial state
  expect(result.current).toEqual([]);

  // Trigger update
  act(() => {
    adaptorStore.setAdaptors(mockAdaptorsList);
  });

  // Verify update
  await waitFor(() => {
    expect(result.current).toEqual(mockAdaptorsList);
  });
});
```

**✅ DO: Test custom selectors**

```typescript
test('useAdaptors with selector returns filtered data', () => {
  const { result } = renderHook(
    () => useAdaptors((state) => state.adaptors.map(a => a.name)),
    { wrapper: SessionProviderWrapper }
  );

  act(() => {
    adaptorStore.setAdaptors(mockAdaptorsList);
  });

  expect(result.current).toEqual([
    '@openfn/language-http',
    '@openfn/language-dhis2',
    '@openfn/language-salesforce',
  ]);
});
```

**❌ DON'T: Test hooks outside of React context**

```typescript
// Bad - hooks need React context
test('bad hook test', () => {
  const result = useAdaptors(); // Error: Invalid hook call
  expect(result).toBeDefined();
});
```

### Testing Async Hooks

**✅ DO: Use waitFor for async updates**

```typescript
test('hook handles async data loading', async () => {
  const { result } = renderHook(() => useAdaptors(), {
    wrapper: createWrapper(),
  });

  // Initial loading state
  expect(result.current).toEqual([]);

  // Trigger async operation
  act(() => {
    adaptorStore.requestAdaptors();
  });

  // Wait for async operation to complete
  await waitFor(
    () => {
      expect(result.current).toHaveLength(3);
    },
    { timeout: 1000 }
  );
});
```

**✅ DO: Handle hook errors gracefully**

```typescript
test('hook handles errors from store', async () => {
  const { result } = renderHook(() => useAdaptorsError(), {
    wrapper: createWrapper(),
  });

  act(() => {
    adaptorStore.setError('Network error');
  });

  await waitFor(() => {
    expect(result.current).toBe('Network error');
  });
});
```

**✅ DO: Test hook cleanup**

```typescript
test('hook cleans up subscriptions', () => {
  const { unmount } = renderHook(() => useSession(), {
    wrapper: createWrapper(),
  });

  const subscriptionCount = sessionStore._getSubscriberCount?.();

  unmount();

  // Verify subscription was cleaned up
  expect(sessionStore._getSubscriberCount?.()).toBeLessThan(
    subscriptionCount
  );
});
```

## React Testing Best Practices (2025)

### Focus on User Behavior, Not Implementation

**✅ DO: Test what users see and do**
```typescript
test('displays loading state to user', () => {
  const { result } = renderHook(() => useAdaptorsLoading(), {
    wrapper: SessionProviderWrapper,
  });

  act(() => {
    adaptorStore.setLoading(true);
  });

  expect(result.current).toBe(true);
  // User would see loading spinner
});
```

**❌ DON'T: Test component internals**
```typescript
test('bad - tests internal state', () => {
  const component = render(<AdaptorList />);
  // Don't do this
  expect(component.instance().state.loading).toBe(true);
});
```

### Testing Custom Hooks

**✅ DO: Use renderHook with proper wrapper**
```typescript
import { renderHook, waitFor } from '@testing-library/react';

function createWrapper() {
  return ({ children }: { children: React.ReactNode }) => (
    <SessionProvider>{children}</SessionProvider>
  );
}

test('custom hook returns expected values', () => {
  const { result } = renderHook(() => useAdaptors(), {
    wrapper: createWrapper(),
  });

  expect(result.current).toBeDefined();
});
```

**✅ DO: Test hook updates with act()**
```typescript
test('hook responds to store changes', async () => {
  const { result } = renderHook(() => useAdaptors(), {
    wrapper: createWrapper(),
  });

  // Wrap state updates in act()
  act(() => {
    adaptorStore.setAdaptors(mockAdaptorsList);
  });

  await waitFor(() => {
    expect(result.current).toHaveLength(3);
  });
});
```

**❌ DON'T: Call hooks directly without renderHook**
```typescript
test('bad - calls hook outside React', () => {
  // This will error: "Invalid hook call"
  const result = useAdaptors();
  expect(result).toBeDefined();
});
```

## Mock Management in React Tests

**✅ DO: Clear mocks between tests**
```typescript
import { vi } from 'vitest';

describe('component tests', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  test('test 1', () => {
    const mockFn = vi.fn();
    // Test logic
  });

  test('test 2', () => {
    // Clean slate - mocks are cleared
  });
});
```

**✅ DO: Use vi.spyOn for tracking method calls**
```typescript
test('component calls store method', () => {
  const requestSpy = vi.spyOn(adaptorStore, 'requestAdaptors');

  const { result } = renderHook(() => useAdaptorCommands(), {
    wrapper: createWrapper(),
  });

  act(() => {
    result.current.requestAdaptors();
  });

  expect(requestSpy).toHaveBeenCalledTimes(1);
  requestSpy.mockRestore();
});
```

## Testing Context Providers

**✅ DO: Test provider value changes**
```typescript
test('SessionProvider updates consumers', () => {
  const TestComponent = () => {
    const session = useSession();
    return <div>{session.isConnected ? 'Connected' : 'Disconnected'}</div>;
  };

  const { getByText } = render(
    <SessionProvider>
      <TestComponent />
    </SessionProvider>
  );

  expect(getByText('Disconnected')).toBeDefined();

  act(() => {
    // Trigger connection
    sessionStore.initializeSession(mockSocket, 'test:room', userData);
  });

  waitFor(() => {
    expect(getByText('Connected')).toBeDefined();
  });
});
```

## Avoid These React Testing Pitfalls

**❌ DON'T: Use implementation details**
```typescript
// Bad - relies on class names and internal structure
expect(container.querySelector('.loading-spinner')).toBeTruthy();

// Good - tests what user sees
expect(screen.getByRole('status', { name: /loading/i })).toBeTruthy();
```

**❌ DON'T: Test library code**
```typescript
// Bad - testing if React context works
test('context provides value', () => {
  const { result } = renderHook(() => useContext(SessionContext));
  expect(result).toBeDefined(); // Just testing React Context API
});

// Good - testing your logic
test('useSession throws outside provider', () => {
  expect(() => {
    renderHook(() => useSession()); // No wrapper
  }).toThrow('useSession must be used within a SessionProvider');
});
```

## Custom Async Helpers

**✅ DO: Create custom async helpers**

```typescript
// __helpers__/testUtils.ts
export async function waitForStoreUpdate<T>(
  store: { getSnapshot: () => T; subscribe: (cb: () => void) => () => void },
  predicate: (state: T) => boolean,
  timeout = 1000
): Promise<T> {
  return new Promise((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      reject(new Error(`Timeout waiting for store update after ${timeout}ms`));
    }, timeout);

    const unsubscribe = store.subscribe(() => {
      const state = store.getSnapshot();
      if (predicate(state)) {
        clearTimeout(timeoutId);
        unsubscribe();
        resolve(state);
      }
    });

    // Check immediately in case condition is already met
    const state = store.getSnapshot();
    if (predicate(state)) {
      clearTimeout(timeoutId);
      unsubscribe();
      resolve(state);
    }
  });
}

// Usage
test('waits for connection', async () => {
  const store = createSessionStore();

  store.initializeSession(mockSocket, 'test:room', userData);

  const state = await waitForStoreUpdate(
    store,
    (s) => s.isConnected === true
  );

  expect(state.isConnected).toBe(true);
});
```

## Additional Resources

- [React Testing Library](https://testing-library.com/react)
- [Testing Best Practices (Kent C. Dodds)](https://kentcdodds.com/blog/common-mistakes-with-react-testing-library)
- [act() Documentation](https://react.dev/reference/react/act)
