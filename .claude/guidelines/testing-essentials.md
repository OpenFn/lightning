# Testing Essentials: Avoiding Over-Testing

## Overview

These guidelines ensure maintainable, readable tests that focus on behavior rather than exhaustive coverage. The priority is avoiding micro-tests.

## Test behavior not implementation

Test what a user or a calling module observes — inputs, outputs, side effects — not internal data structures or private fields. Micro-tests that assert "uses a Map internally" or "notifies subscribers exactly twice" are coupling tests to implementation and will break on refactor without signalling a real regression.

## Group related assertions

Multiple assertions about the same operation belong in one test. Splitting one-property-per-test produces brain-numbing files where the shape is obscured by noise.

**Canonical example:**

```typescript
// ❌ Micro-tests (4 tests, ~20 lines, hides shape)
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

// ✅ One grouped test (reveals the initial state at a glance)
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

**Elixir equivalent** — pattern-match the whole struct rather than asserting one field per test:

```elixir
test "job insert operation updates YDoc with complete job data" do
  # ... setup ...
  assert Yex.Array.length(jobs_array) == 8
  assert %{
    "name" => "New Test Job",
    "body" => "console.log('new job');",
    "adaptor" => "@openfn/language-http@latest"
  } = new_job_data
end
```

### When to separate vs group

**Separate tests when:**
- Different user workflows ("connect" vs "disconnect")
- Different setup requirements ("with data" vs "empty")
- Success vs error paths
- Async vs sync behavior

**Group assertions when:**
- Testing multiple properties of the same operation
- Verifying a state transition (before → action → after)
- Related side effects of a single command

### Quick decision tree

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

## Test file length

**Test files over 400 lines: consolidate.** Group related assertions, extract setup into `test/collaborative-editor/__helpers__/`, and split by behaviour rather than by property. New work already meets this — files added in the last three months run to a median of 196 lines. Roughly half the older suite does not, and the largest file is 1,955 lines; that is legacy, not licence. Nothing enforces this; reviewers do.

## Channel mocks

Phoenix Channel mocks for the collaborative editor are Lightning-specific and live in the test tree, not in these guidelines. `assets/test/collaborative-editor/mocks/phoenixChannel.ts` exports `createMockPhoenixChannel` and `createMockPhoenixChannelProvider`; `assets/test/collaborative-editor/__helpers__/storeHelpers.ts` exports the per-store setup factories that wire a mock channel into a store; `assets/test/collaborative-editor/__helpers__/channelMocks.ts` exports the push-response helpers (`createMockChannelPushOk`, `createMockChannelPushError`, and four more). Read those files rather than reconstructing the mocks.

> `.claude/guidelines/testing/collaborative-editor.md §Channel Mocks` covers what the mock channel exposes beyond the Phoenix `Channel` interface.

## Test structure and organization

### Naming

Use descriptive, complete-sentence test names:

```typescript
test('throws error when used outside SessionProvider', () => {});
test('updates adaptors list and clears loading state', () => {});
test('handles null userData gracefully', () => {});
```

Not `test('it works')`, `test('test1')`, `test('error')`.

### Setup

Extract common setup into `beforeEach` or a factory helper. `assets/test/collaborative-editor/__helpers__/storeHelpers.ts` exports five, one per store shape.

## Async testing

Prefer `waitFor` over arbitrary timeouts, and always `await` the operation you're asserting against:

```typescript
// ✅ Reliable
test('reliable test', async () => {
  triggerAsyncUpdate();
  await waitFor(() => {
    expect(store.getSnapshot().isComplete).toBe(true);
  }, { timeout: 1000 });
});

// ❌ Flaky
test('flaky test', async () => {
  triggerAsyncUpdate();
  await new Promise(resolve => setTimeout(resolve, 10));
  expect(store.getSnapshot().isComplete).toBe(true);
});
```

Forgetting `await` on a promise-returning store command is the single most common cause of "why does this pass sometimes?".

## Running tests

```bash
npm test                             # Run all tests
npm run test:watch                   # Watch mode
npm test -- useSession.test.ts       # Specific file
npm test -- useSession.test.ts:45    # Specific line
npm test -- -t "SessionStore"        # Filter by name
```

## Additional resources

- **React patterns:** `.claude/guidelines/testing/react-patterns.md`
- **Vitest advanced:** `.claude/guidelines/testing/vitest-advanced.md`
- **Collaborative editor:** `.claude/guidelines/testing/collaborative-editor.md` (Y.Doc, Phoenix channel mocks)
