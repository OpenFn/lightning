# Vitest Advanced Features

Lightning-specific fixture and test-data patterns. Vitest is pinned at **3.2.4**. For general Vitest features (AbortSignal, fixtures, conditional skip, `expectTypeOf`, `test.each`, benchmarks) see the [Vitest docs](https://vitest.dev/).

## Cross-references

- Test behavior, not implementation: see `.claude/guidelines/testing-essentials.md §Test behavior not implementation`.
- Lightning store roster (SessionStore, WorkflowStore, AwarenessStore, SessionContextStore, AdaptorStore, CredentialStore): see `.claude/guidelines/store-structure.md`.
- Phoenix channel mock helper (`createMockPhoenixChannel`): see `.claude/guidelines/testing/collaborative-editor.md §Channel Mocks`.

## Lightning adaptor fixtures

Adaptors follow a fixed shape driven by the `@openfn/language-*` registry. Use a dedicated fixtures file rather than inline objects: `assets/test/collaborative-editor/fixtures/adaptorData.ts` already holds `mockAdaptor`, `mockAdaptorVersions`, `mockAdaptorsList`, four more named adaptors, and two override-taking factories (`createMockAdaptor`, `createMockAdaptorsList`). Import from there rather than writing a new one.

## Test isolation for Lightning stores

Each Lightning store holds subscriber state. Always construct a fresh store per test to avoid cross-test leakage.

```typescript
describe('adaptor store', () => {
  let store: AdaptorStoreInstance;

  beforeEach(() => {
    store = createAdaptorStore();
  });

  test('loading flag toggles', () => {
    store.setLoading(true);
    expect(store.getSnapshot().isLoading).toBe(true);
  });
});
```
