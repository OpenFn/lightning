# Vitest Advanced Features

Lightning-specific fixture and test-data patterns. Vitest is pinned at **3.2.4**. For general Vitest features (AbortSignal, fixtures, conditional skip, `expectTypeOf`, `test.each`, benchmarks) see the [Vitest docs](https://vitest.dev/).

## Cross-references

- Test behavior, not implementation: see `.claude/guidelines/testing-essentials.md §Test behavior not implementation`.
- Lightning store roster (SessionStore, WorkflowStore, AwarenessStore, SessionContextStore, AdaptorStore, CredentialStore): see `.claude/guidelines/store-structure.md`.
- Phoenix channel mock helper (`createMockPhoenixChannel`): see `.claude/guidelines/testing/collaborative-editor.md §Channel Mocks`.

## Lightning adaptor fixtures

Adaptors follow a fixed shape driven by the `@openfn/language-*` registry. Use a dedicated fixtures file rather than inline objects.

```typescript
// fixtures/adaptorData.ts
export const mockAdaptor: Adaptor = {
  name: '@openfn/language-http',
  versions: [{ version: '2.1.0' }, { version: '2.0.5' }],
  repo: 'https://github.com/OpenFn/adaptors/tree/main/packages/http',
  latest: '2.1.0',
};

export const mockAdaptorsList: Adaptor[] = [
  mockAdaptor,
  mockAdaptorDhis2,
  mockAdaptorSalesforce,
];
```

### Adaptor builder for flexible data

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
```

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
