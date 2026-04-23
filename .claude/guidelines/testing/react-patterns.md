# React Testing Patterns

Lightning-specific React Testing Library patterns. For general RTL, `act()`, `waitFor`, `renderHook`, and `userEvent` usage see the [React Testing Library docs](https://testing-library.com/react).

## Cross-references

- Test behavior, not implementation: see `.claude/guidelines/testing-essentials.md §Test behavior not implementation`.
- Lightning store roster (SessionStore, WorkflowStore, AwarenessStore, SessionContextStore, AdaptorStore, CredentialStore): see `.claude/guidelines/store-structure.md`.
- Phoenix channel mock helper (`createMockPhoenixChannel`): see `.claude/guidelines/testing/collaborative-editor.md §Channel Mocks`.
- Test file length rule (400 lines): see `.claude/guidelines/testing-essentials.md §Test file length`.

## Lightning-specific hook patterns

When a Lightning hook subscribes to a store from the roster above, the test wrapper must provide that store via its Provider. Channel emissions that drive store updates must be wrapped in `act()` because they occur outside React's batching.

```typescript
test('channel emission drives hook state', async () => {
  const mockChannel = createMockPhoenixChannel();
  store._connectChannel(createMockPhoenixChannelProvider(mockChannel));

  const { result } = renderHook(() => useSessionContext(), {
    wrapper: createWrapper(store),
  });

  act(() => {
    mockChannel._test.emit('session_context', {
      user: mockUser,
      config: mockConfig,
    });
  });

  await waitFor(() => {
    expect(result.current.user).toEqual(mockUser);
  });
});
```

## Testing store-backed custom hooks

Subscriptions created inside a hook must be cleaned up on unmount. For Lightning stores that expose a subscriber count for diagnostics:

```typescript
test('hook cleans up store subscriptions', () => {
  const { unmount } = renderHook(() => useSession(), {
    wrapper: createWrapper(),
  });

  const before = sessionStore._getSubscriberCount?.();
  unmount();
  expect(sessionStore._getSubscriberCount?.()).toBeLessThan(before);
});
```

## Context-provider tests

Lightning uses a provider per top-level store (SessionProvider, AdaptorProvider, etc.). When asserting "outside provider" behavior, run the hook without a wrapper and assert the thrown error message — the error text is part of the provider contract and is project-specific.

```typescript
test('useSession throws outside provider', () => {
  expect(() => renderHook(() => useSession())).toThrow(
    'useSession must be used within a SessionProvider'
  );
});
```
