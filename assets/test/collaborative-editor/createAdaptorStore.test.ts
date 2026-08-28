/**
 * Tests for createAdaptorStore
 *
 * Covers the core store interface (subscribe/getSnapshot), state management
 * commands, HTTP-backed `requestAdaptors`, Phoenix channel `adaptors_updated`
 * live-update handling, and query helpers.
 */

import { describe, test, expect, vi, beforeEach } from 'vitest';

import * as adaptorsApi from '../../js/collaborative-editor/api/adaptors';
import { createAdaptorStore } from '../../js/collaborative-editor/stores/createAdaptorStore';
import type { AdaptorStoreInstance } from '../../js/collaborative-editor/stores/createAdaptorStore';

import {
  mockAdaptorsList,
  mockAdaptor,
  mockAdaptorGmail,
  invalidAdaptorData,
} from './fixtures/adaptorData.js';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  waitForCondition,
} from './mocks/phoenixChannel.js';
import type {
  MockPhoenixChannel,
  MockPhoenixChannelProvider,
} from './mocks/phoenixChannel.js';

vi.mock('../../js/collaborative-editor/api/adaptors');

const getAdaptorCatalogueMock = vi.mocked(adaptorsApi.getAdaptorCatalogue);

// Define fixture types
interface AdaptorTestFixtures {
  store: AdaptorStoreInstance;
  mockChannel: MockPhoenixChannel;
  mockProvider: MockPhoenixChannelProvider;
}

const adaptorTest = test.extend<AdaptorTestFixtures>({
  store: async ({}, use) => {
    await use(createAdaptorStore());
  },
  mockChannel: async ({}, use) => {
    await use(createMockPhoenixChannel());
  },
  mockProvider: async ({ mockChannel }, use) => {
    await use(createMockPhoenixChannelProvider(mockChannel));
  },
});

// Helper to create expected sorted adaptors (alphabetically by name, versions descending)
function getSortedAdaptors(adaptors: any[]) {
  return [...adaptors]
    .sort((a, b) => a.name.localeCompare(b.name))
    .map(adaptor => ({
      ...adaptor,
      versions: [...adaptor.versions].sort((a, b) => b.localeCompare(a)),
    }));
}

beforeEach(() => {
  getAdaptorCatalogueMock.mockReset();
});

describe('createAdaptorStore', () => {
  test('initializes with default state', () => {
    const store = createAdaptorStore();
    expect(store.getSnapshot()).toEqual({
      adaptors: [],
      isLoading: false,
      error: null,
      lastUpdated: null,
    });
  });

  test('subscribe/unsubscribe and multiple subscribers behave correctly', () => {
    const store = createAdaptorStore();
    let count1 = 0;
    let count2 = 0;
    const unsubscribe1 = store.subscribe(() => count1++);
    const unsubscribe2 = store.subscribe(() => count2++);

    store.setLoading(true);
    expect(count1).toBe(1);
    expect(count2).toBe(1);

    unsubscribe2();
    store.clearError();
    expect(count1).toBe(2);
    expect(count2).toBe(1); // unsubscribed, no longer notified

    unsubscribe1();
    store.setLoading(false);
    expect(count1).toBe(2); // unsubscribed, no longer notified
  });

  test('withSelector returns a referentially stable value until its slice changes', () => {
    const store = createAdaptorStore();
    const selectAdaptors = store.withSelector(state => state.adaptors);
    const selectIsLoading = store.withSelector(state => state.isLoading);

    const adaptorsBefore = selectAdaptors();
    const loadingBefore = selectIsLoading();

    store.setLoading(true);

    expect(selectAdaptors()).toBe(adaptorsBefore); // unrelated slice unchanged
    expect(selectIsLoading()).not.toBe(loadingBefore);
  });

  test('setLoading/setError/clearError/setAdaptors transition state as expected', () => {
    const store = createAdaptorStore();

    store.setLoading(true);
    expect(store.getSnapshot().isLoading).toBe(true);

    store.setError('Test error message');
    let state = store.getSnapshot();
    expect(state.error).toBe('Test error message');
    expect(state.isLoading).toBe(false); // setError clears loading

    store.clearError();
    expect(store.getSnapshot().error).toBeNull();

    const timestamp = Date.now();
    store.setAdaptors(mockAdaptorsList);
    state = store.getSnapshot();
    expect(state.adaptors).toEqual(mockAdaptorsList);
    expect(state.error).toBeNull();
    expect(state.lastUpdated).toBeGreaterThanOrEqual(timestamp);
  });

  describe('requestAdaptors (HTTP)', () => {
    test('fetches, validates, sorts and stores a valid catalogue', async () => {
      getAdaptorCatalogueMock.mockResolvedValue({ data: mockAdaptorsList });
      const store = createAdaptorStore();

      await store.requestAdaptors();

      const state = store.getSnapshot();
      expect(state.adaptors).toEqual(getSortedAdaptors(mockAdaptorsList));
      expect(state.isLoading).toBe(false);
      expect(state.error).toBeNull();
      expect(state.lastUpdated).toBeGreaterThan(0);
    });

    test('records a validation error and leaves adaptors empty on invalid entries', async () => {
      getAdaptorCatalogueMock.mockResolvedValue({
        data: [invalidAdaptorData.missingName],
      });
      const store = createAdaptorStore();

      await store.requestAdaptors();

      const state = store.getSnapshot();
      expect(state.adaptors).toHaveLength(0);
      expect(state.isLoading).toBe(false);
      expect(state.error).toContain('Invalid adaptors data');
    });

    test('records an error when the fetch itself rejects', async () => {
      getAdaptorCatalogueMock.mockRejectedValue(new Error('Server error'));
      const store = createAdaptorStore();

      await store.requestAdaptors();

      const state = store.getSnapshot();
      expect(state.adaptors).toHaveLength(0);
      expect(state.error).toContain('Failed to request adaptors');
      expect(state.isLoading).toBe(false);
    });

    test('sets isLoading synchronously while the request is in flight', async () => {
      let resolveFetch: (value: {
        data: typeof mockAdaptorsList;
      }) => void = () => {};
      getAdaptorCatalogueMock.mockReturnValue(
        new Promise(resolve => {
          resolveFetch = resolve;
        })
      );
      const store = createAdaptorStore();

      const pending = store.requestAdaptors();
      expect(store.getSnapshot().isLoading).toBe(true);

      resolveFetch({ data: mockAdaptorsList });
      await pending;

      expect(store.getSnapshot().isLoading).toBe(false);
    });

    test('clears a stale error from a previous failed fetch as soon as a retry starts', async () => {
      getAdaptorCatalogueMock.mockRejectedValueOnce(new Error('Server error'));
      const store = createAdaptorStore();
      await store.requestAdaptors();
      expect(store.getSnapshot().error).toContain('Failed to request adaptors');

      getAdaptorCatalogueMock.mockResolvedValueOnce({ data: mockAdaptorsList });
      const pending = store.requestAdaptors();
      expect(store.getSnapshot().error).toBeNull();

      await pending;
      expect(store.getSnapshot().error).toBeNull();
    });
  });

  describe('channel connection and adaptors_updated events', () => {
    adaptorTest(
      'connectChannel refreshes the catalogue over HTTP so a reconnect picks up new adaptors',
      async ({ store, mockProvider }) => {
        getAdaptorCatalogueMock.mockResolvedValue({ data: mockAdaptorsList });

        const cleanup = store._connectChannel(mockProvider as any);

        await waitForCondition(() => store.getSnapshot().adaptors.length > 0);

        expect(getAdaptorCatalogueMock).toHaveBeenCalledTimes(1);
        expect(store.getSnapshot().adaptors).toEqual(
          getSortedAdaptors(mockAdaptorsList)
        );
        cleanup();
      }
    );

    adaptorTest(
      'an adaptors_updated push for a brand-new adaptor re-fetches over HTTP and adds it to the catalogue',
      async ({ store, mockChannel, mockProvider }) => {
        getAdaptorCatalogueMock.mockResolvedValueOnce({
          data: mockAdaptorsList,
        });
        const cleanup = store._connectChannel(mockProvider as any);

        await waitForCondition(() => store.getSnapshot().adaptors.length > 0);
        expect(store.getSnapshot().adaptors).toEqual(
          getSortedAdaptors(mockAdaptorsList)
        );

        const catalogueWithGmail = [...mockAdaptorsList, mockAdaptorGmail];
        getAdaptorCatalogueMock.mockResolvedValueOnce({
          data: catalogueWithGmail,
        });

        mockChannel._test.emit('adaptors_updated', {
          names: ['@openfn/language-gmail'],
        });

        await waitForCondition(() =>
          store
            .getSnapshot()
            .adaptors.some(a => a.name === '@openfn/language-gmail')
        );

        expect(getAdaptorCatalogueMock).toHaveBeenCalledTimes(2);
        expect(store.getSnapshot().adaptors).toEqual(
          getSortedAdaptors(catalogueWithGmail)
        );
        expect(store.getSnapshot().error).toBeNull();
        cleanup();
      }
    );

    adaptorTest(
      'an adaptors_updated push for an already-shown adaptor re-fetches and updates its version list',
      async ({ store, mockChannel, mockProvider }) => {
        getAdaptorCatalogueMock.mockResolvedValueOnce({
          data: mockAdaptorsList,
        });
        const cleanup = store._connectChannel(mockProvider as any);

        await waitForCondition(() => store.getSnapshot().adaptors.length > 0);

        const bumpedHttp = {
          ...mockAdaptor,
          versions: ['2.2.0', ...mockAdaptor.versions],
          latest_version: '2.2.0',
        };
        const catalogueWithBump = mockAdaptorsList.map(a =>
          a.name === mockAdaptor.name ? bumpedHttp : a
        );
        getAdaptorCatalogueMock.mockResolvedValueOnce({
          data: catalogueWithBump,
        });

        mockChannel._test.emit('adaptors_updated', {
          names: ['@openfn/language-http'],
        });

        await waitForCondition(
          () =>
            store.findAdaptorByName('@openfn/language-http')?.latest_version !==
            '2.1.0'
        );

        expect(getAdaptorCatalogueMock).toHaveBeenCalledTimes(2);
        expect(store.getSnapshot().adaptors).toEqual(
          getSortedAdaptors(catalogueWithBump)
        );
        expect(store.getSnapshot().error).toBeNull();
        cleanup();
      }
    );

    test('throws when connecting with a null/undefined provider', () => {
      const store = createAdaptorStore();
      expect(() => store._connectChannel(null as any)).toThrow(TypeError);
      expect(() => store._connectChannel(undefined as any)).toThrow(TypeError);
    });
  });

  describe('query helpers', () => {
    test('findAdaptorByName/getLatestVersion/getVersions look up by name', () => {
      const store = createAdaptorStore();
      store.setAdaptors(mockAdaptorsList);

      expect(store.findAdaptorByName('@openfn/language-http')).toEqual(
        mockAdaptor
      );
      expect(
        store.findAdaptorByName('@openfn/language-nonexistent')
      ).toBeNull();

      expect(store.getLatestVersion('@openfn/language-http')).toBe('2.1.0');
      expect(store.getLatestVersion('@openfn/language-nonexistent')).toBeNull();

      expect(store.getVersions('@openfn/language-http')).toEqual(
        mockAdaptor.versions
      );
      expect(store.getVersions('@openfn/language-nonexistent')).toHaveLength(0);
    });
  });

  describe('handleAdaptorsReceived merge-by-name', () => {
    test('preserves referential identity across identical loads', async () => {
      getAdaptorCatalogueMock.mockResolvedValue({ data: mockAdaptorsList });
      const store = createAdaptorStore();
      await store.requestAdaptors();

      const selectAdaptors = store.withSelector(state => state.adaptors);
      const firstRef = selectAdaptors();

      await store.requestAdaptors();

      const secondRef = selectAdaptors();
      expect(secondRef).toBe(firstRef);
      secondRef.forEach((adaptor, i) => {
        expect(adaptor).toBe(firstRef[i]);
      });
    });

    test('replaces only the changed entry when one adaptor mutates', async () => {
      getAdaptorCatalogueMock.mockResolvedValue({ data: mockAdaptorsList });
      const store = createAdaptorStore();
      await store.requestAdaptors();

      const beforeByName = new Map(
        store.getSnapshot().adaptors.map(a => [a.name, a])
      );

      const target = mockAdaptorsList[0]!;
      const mutated = mockAdaptorsList.map(a =>
        a.name === target.name
          ? {
              ...a,
              versions: ['99.0.0', ...a.versions],
              latest_version: '99.0.0',
            }
          : a
      );
      getAdaptorCatalogueMock.mockResolvedValue({ data: mutated });
      await store.requestAdaptors();

      for (const adaptor of store.getSnapshot().adaptors) {
        if (adaptor.name === target.name) {
          expect(adaptor).not.toBe(beforeByName.get(adaptor.name));
        } else {
          expect(adaptor).toBe(beforeByName.get(adaptor.name));
        }
      }
    });
  });
});
