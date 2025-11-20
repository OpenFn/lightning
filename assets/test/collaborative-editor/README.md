# Collaborative Editor Tests

## Overview

This directory contains comprehensive tests for Lightning's collaborative editor
system, including stores, hooks, components, and utilities that power real-time
collaborative workflow editing.

## Test Structure

```
assets/test/collaborative-editor/
├── __helpers__/           # Shared test utilities and mocks
│   ├── channelMocks.ts    # Phoenix channel mock factories
│   ├── storeHelpers.ts    # Store setup utilities
│   └── ...
├── __fixtures__/          # Test data fixtures
├── stores/                # Store unit tests
├── hooks/                 # React hook tests (using RTL)
├── components/            # React component tests (using RTL)
├── contexts/              # Context provider tests
├── utils/                 # Utility function tests
└── types/                 # Type/schema validation tests
```

## Running Tests

```bash
# Navigate to assets directory first
cd assets

# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Run tests with coverage report
npm run test:coverage

# Run specific test file
npm test -- useSession.test.ts

# Run tests matching a pattern
npm test -- SessionContext
```

## Test Technologies

- **Vitest**: Testing framework (fast, ESM-native)
- **React Testing Library**: Component and hook testing
- **@testing-library/user-event**: User interaction simulation
- **Yjs**: CRDT mocks for collaborative editing tests
- **Phoenix Channels**: WebSocket communication mocks

## Writing Tests

### General Principles

1. **Follow unit-test-guidelines.md** in .context/ directory
2. **Test behavior, not implementation**: Focus on what users/components see and
   do
3. **Use semantic queries**: Prefer `getByRole`, `getByText` over `getByTestId`
4. **Test accessibility**: Verify ARIA attributes, keyboard navigation
5. **Avoid arbitrary timeouts**: Use `waitFor` with conditions instead
6. **Keep tests focused**: One assertion per concept, clear test names

### Store Tests

Store tests verify business logic and state management:

```typescript
import { createAdaptorStore } from '../../../js/collaborative-editor/stores/createAdaptorStore';

describe('createAdaptorStore', () => {
  test('initializes with empty state', () => {
    const store = createAdaptorStore();
    const snapshot = store.getSnapshot();

    expect(snapshot.adaptors).toEqual([]);
    expect(snapshot.isLoading).toBe(false);
  });
});
```

**Important**: Test the store logic, not the framework (Zustand). Focus on:

- Initial state
- State transitions
- Business logic
- Error handling
- Cleanup

### Hook Tests

Use `renderHook` from React Testing Library to test actual React hooks:

```typescript
import { renderHook, waitFor } from '@testing-library/react';
import { useSession } from '../../../js/collaborative-editor/hooks/useSession';

describe('useSession', () => {
  test('subscribes to store on mount', () => {
    const { result } = renderHook(() => useSession(), {
      wrapper: createWrapper(),
    });

    expect(result.current.isConnected).toBe(false);
  });

  test('cleans up subscription on unmount', () => {
    const { unmount } = renderHook(() => useSession(), {
      wrapper: createWrapper(),
    });

    unmount();
    // Verify cleanup happened
  });
});
```

**Important**:

- Test actual React lifecycle (mount, update, unmount)
- Test subscription management
- Test selector memoization
- Use proper wrappers (StoreProvider, etc.)

### Component Tests

Test actual component rendering and user interactions:

```typescript
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

describe('EmailVerificationBanner', () => {
  test('shows danger banner when grace period expired', () => {
    render(
      <EmailVerificationBanner
        user={{ email_verified: false }}
        config={{ grace_period_state: 'expired' }}
      />
    );

    const alert = screen.getByRole('alert');
    expect(alert).toHaveClass('bg-red-50');
  });
});
```

**Important**:

- Use semantic queries (`getByRole`, `getByLabelText`)
- Test accessibility (ARIA attributes)
- Test user interactions with `userEvent`
- Test what users see, not implementation details

### Test Patterns

#### Parameterized Tests

Use `test.each` for testing multiple similar cases:

```typescript
test.each([
  { input: 'January', expected: true },
  { input: 'February', expected: true },
  { input: 'InvalidMonth', expected: false },
])('validates month $input correctly', ({ input, expected }) => {
  const result = monthSchema.safeParse(input);
  expect(result.success).toBe(expected);
});
```

#### Async Testing

Use `waitFor` for async operations, never arbitrary timeouts:

```typescript
// ❌ BAD - Arbitrary timeout
await new Promise(resolve => setTimeout(resolve, 100));
expect(store.getSnapshot().isLoading).toBe(false);

// ✅ GOOD - Wait for condition
await waitFor(() => {
  expect(store.getSnapshot().isLoading).toBe(false);
});
```

#### Helper Functions

Reuse setup code via **helpers**/:

```typescript
import { createMockPhoenixChannel } from '../__helpers__/channelMocks';
import { setupAdaptorStoreTest } from '../__helpers__/storeHelpers';
```

## Test Coverage

Target coverage levels:

- **Lines**: ≥80%
- **Functions**: ≥80%
- **Branches**: ≥80%
- **Statements**: ≥80%

View coverage report:

```bash
npm run test:coverage
# Opens HTML report in browser
```

## Common Issues

### "Must be used within a StoreProvider" Error

Hook tests need proper wrapper:

```typescript
const { result } = renderHook(() => useSession(), {
  wrapper: ({ children }) => <StoreProvider>{children}</StoreProvider>,
});
```

### Flaky Tests

- Replace arbitrary timeouts with `waitFor`
- Ensure proper cleanup in `afterEach`
- Check for race conditions in async tests
- Use `act()` for state updates

### Memory Leaks

- Always unmount components in tests
- Clean up subscriptions
- Clear timers/intervals
- Check for lingering event listeners

## Code Quality

All tests must pass these checks before commit:

```bash
# Run linting
npm run lint

# Run type checking
npx tsc --noEmit --project ./tsconfig.browser.json

# Run all tests
npm test

# Check coverage
npm run test:coverage
```

## Contributing

When adding new tests:

1. Follow existing patterns in similar test files
2. Add helpers to **helpers**/ for reusable setup
3. Update this README if introducing new patterns
4. Ensure tests are deterministic (no flakiness)
5. Run full test suite before committing

## Test Organization

### Store Tests

Tests for state management stores that handle business logic:

- **createAdaptorStore.test.ts**: Adaptor data management and channel
  integration
- **createSessionStore.test.ts**: YDoc, provider, and awareness lifecycle
- **createSessionContextStore.\*.test.ts**: User, project, and config context
  (split into 3 files for maintainability)

### Hook Tests

Tests for React hooks that provide component-level access to stores:

- **useAdaptors.test.tsx**: Adaptor hooks (useAdaptors, useAdaptorsLoading,
  useAdaptorCommands, etc.)
- **useSession.test.tsx**: Session hook with selectors and lifecycle
- **useSessionContext.test.tsx**: Context hooks (useUser, useProject,
  useAppConfig, etc.)

### Component Tests

Tests for React components using React Testing Library:

- **CollaborativeEditor.test.tsx**: Breadcrumb rendering with store-first
  pattern
- **EmailVerificationBanner.test.tsx**: Conditional banner display with deadline
  formatting
- **StoreProvider.test.tsx**: Context provider and store initialization

### Utility Tests

Tests for pure utility functions:

- **avatar.test.ts**: Avatar initials generation
- **dateFormatting.test.ts**: Deadline calculation and formatting
- **sessionContext.test.ts**: Zod schema validation

## Helper Libraries

### **helpers**/channelMocks.ts

Factories for creating Phoenix channel mocks:

- `createMockPhoenixChannel()` - Basic channel mock
- `createMockPushWithResponse()` - Configurable push response
- `createMockChannelWithResponses()` - Pre-configured channel
- `createMockChannelWithError()` - Error response channel
- `createMockChannelWithTimeout()` - Timeout channel

### **helpers**/storeHelpers.ts

Factories for setting up stores with common configurations:

- `setupAdaptorStoreTest()` - Adaptor store with channel
- `setupSessionContextStoreTest()` - Session context store with channel
- `setupSessionStoreTest()` - Session store with YDoc and provider
- `setupMultipleStores()` - Multiple stores for integration tests

### **helpers**/storeProviderHelpers.ts

React Testing Library wrappers for provider tests:

- `createTestWrapper()` - StoreProvider wrapper
- `createSessionProviderWrapper()` - SessionProvider wrapper
- Test utilities for verifying provider behavior

### **helpers**/breadcrumbHelpers.ts

Utilities for testing breadcrumb logic:

- `createMockProject()` - Mock project data
- `selectBreadcrumbProjectData()` - Store-first selection logic
- `generateBreadcrumbStructure()` - Complete breadcrumb array
- `createBreadcrumbScenario()` - Common test scenarios

### **helpers**/sessionStoreHelpers.ts

Advanced session store test utilities:

- `triggerProviderStatus()` - Simulate provider status changes
- `triggerProviderSync()` - Simulate sync events
- `applyProviderUpdate()` - Apply YDoc updates
- `waitForState()` - Wait for specific state conditions

### **helpers**/sessionContextHelpers.ts

Session context test data builders:

- Mock user, project, and config factory functions
- Common test scenarios for authenticated/unauthenticated states

## Fixtures

The `__fixtures__/` directory contains reusable test data:

### fixtures/adaptorData.ts

Mock adaptor data structures:

- `mockAdaptor` - Sample HTTP adaptor
- `mockAdaptorsList` - List of mock adaptors
- `invalidAdaptorData` - Invalid data for error testing
- `createMockAdaptor()` - Factory for custom adaptors

### fixtures/sessionContextData.ts

Mock session context data:

- `mockUserContext` - Sample user data
- `mockProjectContext` - Sample project data
- `mockAppConfig` - Sample app configuration
- `mockSessionContextResponse` - Complete context response
- Factory functions for creating custom data

## Resources

- [unit-test-guidelines.md](../../../.context/unit-test-guidelines.md) -
  Comprehensive testing guidelines
- [React Testing Library Docs](https://testing-library.com/docs/react-testing-library/intro/)
- [Vitest Docs](https://vitest.dev/)
- [Lightning Architecture](../../../CLAUDE.md) - Project overview

## Test File Naming

Follow these naming conventions:

- **Store tests**: `createXStore.test.ts` (matches store file name)
- **Hook tests**: `useXHook.test.tsx` (matches hook file name, TSX for React
  imports)
- **Component tests**: `ComponentName.test.tsx` (matches component file name)
- **Util tests**: `utilName.test.ts` (matches util file name)
- **Helper files**: No `.test.` suffix, placed in `__helpers__/`
- **Fixture files**: No `.test.` suffix, placed in `__fixtures__/` or
  `fixtures/`

## Test Structure Best Practices

### Describe Block Organization

Group tests logically with nested describe blocks:

```typescript
describe('createAdaptorStore', () => {
  describe('initialization', () => {
    test('getSnapshot returns initial state', () => { ... });
  });

  describe('state management', () => {
    describe('loading state', () => {
      test('setLoading updates loading state', () => { ... });
    });

    describe('error state', () => {
      test('setError updates error state', () => { ... });
    });
  });
});
```

### Test Names

Write clear, descriptive test names:

```typescript
// ❌ BAD - Vague
test('works', () => { ... });
test('test user hook', () => { ... });

// ✅ GOOD - Descriptive
test('returns null when user is not yet loaded', () => { ... });
test('updates when user data changes via channel message', () => { ... });
```

### Arrange-Act-Assert Pattern

Structure tests consistently:

```typescript
test('updates when loading state changes', () => {
  // Arrange - Set up test conditions
  const store = createSessionContextStore();
  const { result } = renderHook(() => useSessionContextLoading(), {
    wrapper: createWrapper(store),
  });

  // Act - Perform the action
  act(() => {
    store.setLoading(true);
  });

  // Assert - Verify the outcome
  expect(result.current).toBe(true);
});
```

## Debugging Tests

### View Test Output

```bash
# Run single test file with full output
npm test -- useSession.test.ts --reporter=verbose

# Run with UI for debugging
npm test -- --ui

# Run in browser for step debugging
npm test -- --browser
```

### Common Debugging Techniques

1. **Add console.log strategically**: Before renders, after state changes
2. **Use screen.debug()**: Dump current DOM state
3. **Check act() warnings**: Indicate async state updates not wrapped properly
4. **Verify cleanup**: Ensure subscriptions and timers are cleaned up
5. **Check for race conditions**: Use waitFor with clear conditions

## Performance Considerations

### Test Speed

- Keep tests focused and isolated
- Use concurrent describe blocks where possible: `describe.concurrent()`
- Avoid unnecessary network/file system operations
- Mock heavy operations
- Use Vitest's built-in parallelization

### Memory Usage

- Clean up stores, subscriptions, timers in afterEach
- Don't create excessive test data
- Unmount components after tests
- Use weak references where appropriate

## Maintenance

### Updating Tests

When updating production code:

1. **Update tests first** (TDD approach when possible)
2. **Run affected tests**: `npm test -- --changed`
3. **Update snapshots if needed**: `npm test -- -u` (use sparingly)
4. **Verify full suite**: `npm test` before committing

### Refactoring Tests

Signs tests need refactoring:

- Tests are brittle (break with minor changes)
- Tests are slow (> 100ms for unit tests)
- Tests are hard to understand
- Tests have duplicate setup code
- Tests test implementation, not behavior

Actions:

- Extract helpers to **helpers**/
- Use test.each for parameterized tests
- Simplify assertions
- Focus on user-facing behavior
- Remove redundant tests
