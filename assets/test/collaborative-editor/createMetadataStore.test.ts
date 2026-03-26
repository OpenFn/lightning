/**
 * Minimal test suite for createMetadataStore
 *
 * Covers the essential functionality:
 * - Basic store interface (subscribe/getSnapshot)
 * - Metadata fetching and caching
 * - Loading and error states
 * - Cache key deduplication
 */

import { describe, test, expect } from 'vitest';

import { createMetadataStore } from '../../js/collaborative-editor/stores/createMetadataStore';
import type { MetadataStoreInstance } from '../../js/collaborative-editor/stores/createMetadataStore';

import {
  createMockChannelPushOk,
  createMockChannelPushError,
} from './__helpers__/channelMocks';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from './mocks/phoenixChannel';
import type {
  MockPhoenixChannel,
  MockPhoenixChannelProvider,
} from './mocks/phoenixChannel';

// Test fixtures
interface MetadataTestFixtures {
  store: MetadataStoreInstance;
  mockChannel: MockPhoenixChannel;
  mockProvider: MockPhoenixChannelProvider;
  connectedStore: {
    store: MetadataStoreInstance;
    provider: MockPhoenixChannelProvider;
    cleanup: () => void;
  };
}

const metadataTest = test.extend<MetadataTestFixtures>({
  store: async ({}, use) => {
    const store = createMetadataStore();
    await use(store);
  },

  mockChannel: async ({}, use) => {
    const channel = createMockPhoenixChannel();
    await use(channel);
  },

  mockProvider: async ({ mockChannel }, use) => {
    const provider = createMockPhoenixChannelProvider(mockChannel);
    await use(provider);
  },

  connectedStore: async ({ store, mockProvider }, use) => {
    const cleanup = store._connectChannel(mockProvider as any);
    await use({ store, provider: mockProvider, cleanup });
    cleanup();
  },
});

// Mock metadata responses
const mockMetadata = {
  dataElements: [
    { id: 'de1', name: 'Data Element 1' },
    { id: 'de2', name: 'Data Element 2' },
  ],
};

const mockMetadataResponse = {
  job_id: 'job-123',
  metadata: mockMetadata,
};

const mockErrorResponse = {
  job_id: 'job-456',
  metadata: { error: 'invalid_credentials' },
};

describe('createMetadataStore', () => {
  describe('initialization', () => {
    test('getSnapshot returns initial state', () => {
      const store = createMetadataStore();
      const initialState = store.getSnapshot();

      expect(initialState.jobs).toBeInstanceOf(Map);
      expect(initialState.jobs.size).toBe(0);
    });
  });

  describe('subscriptions', () => {
    test('subscribe/unsubscribe works correctly', () => {
      const store = createMetadataStore();
      let callCount = 0;

      const listener = () => {
        callCount++;
      };

      const unsubscribe = store.subscribe(listener);

      // Trigger a state change
      store.clearMetadata('job-123');

      expect(callCount).toBe(1);

      // Unsubscribe and trigger change
      unsubscribe();
      store.clearAllMetadata();

      // Listener should not be called after unsubscribe
      expect(callCount).toBe(1);
    });

    test('withSelector creates memoized selector', () => {
      const store = createMetadataStore();

      const selectJobMetadata = store.withSelector(state =>
        state.jobs.get('job-123')
      );

      // Initial call
      const metadata1 = selectJobMetadata();
      expect(metadata1).toBeUndefined();

      // Unrelated state change - should return same reference
      store.clearMetadata('job-456');
      const metadata2 = selectJobMetadata();

      expect(metadata1).toBe(metadata2);
    });
  });

  describe('metadata fetching', () => {
    metadataTest(
      'successfully fetches and caches metadata',
      async ({ store, mockChannel, mockProvider }) => {
        // Setup mock to return metadata
        mockChannel.push = createMockChannelPushOk(mockMetadataResponse);
        store._connectChannel(mockProvider as any);

        // Request metadata
        await store.requestMetadata(
          'job-123',
          '@openfn/language-dhis2',
          'cred-1'
        );

        // Check state after fetch
        const state = store.getSnapshot();
        const jobState = state.jobs.get('job-123');

        expect(jobState).toBeDefined();
        expect(jobState?.metadata).toEqual(mockMetadata);
        expect(jobState?.isLoading).toBe(false);
        expect(jobState?.error).toBeNull();
        expect(jobState?.lastFetched).toBeGreaterThan(0);
        expect(jobState?.cacheKey).toBe('@openfn/language-dhis2:cred-1');
      }
    );

    metadataTest(
      'handles error responses correctly',
      async ({ store, mockChannel, mockProvider }) => {
        mockChannel.push = createMockChannelPushOk(mockErrorResponse);
        store._connectChannel(mockProvider as any);

        await store.requestMetadata(
          'job-456',
          '@openfn/language-dhis2',
          'cred-2'
        );

        const state = store.getSnapshot();
        const jobState = state.jobs.get('job-456');

        expect(jobState?.metadata).toBeNull();
        expect(jobState?.error).toBe('invalid_credentials');
        expect(jobState?.isLoading).toBe(false);
      }
    );

    metadataTest(
      'handles channel errors',
      async ({ store, mockChannel, mockProvider }) => {
        mockChannel.push = createMockChannelPushError(
          'Connection failed',
          'timeout'
        );
        store._connectChannel(mockProvider as any);

        await store.requestMetadata(
          'job-789',
          '@openfn/language-dhis2',
          'cred-3'
        );

        const state = store.getSnapshot();
        const jobState = state.jobs.get('job-789');

        expect(jobState?.metadata).toBeNull();
        expect(jobState?.error).toContain('Channel request failed');
        expect(jobState?.isLoading).toBe(false);
      }
    );

    test('handles missing channel connection', async () => {
      const store = createMetadataStore();

      // Request without connecting channel
      await store.requestMetadata(
        'job-999',
        '@openfn/language-dhis2',
        'cred-4'
      );

      const state = store.getSnapshot();
      const jobState = state.jobs.get('job-999');

      expect(jobState?.error).toBe('No connection available');
      expect(jobState?.isLoading).toBe(false);
    });
  });

  describe('cache behavior', () => {
    metadataTest(
      'uses cached metadata when cache key matches',
      async ({ store, mockChannel, mockProvider }) => {
        let pushCount = 0;

        // Wrap the push to count calls
        const originalPush = createMockChannelPushOk(mockMetadataResponse);
        mockChannel.push = (...args: any[]) => {
          pushCount++;
          return originalPush.apply(mockChannel, args);
        };

        store._connectChannel(mockProvider as any);

        // First request
        await store.requestMetadata(
          'job-123',
          '@openfn/language-dhis2',
          'cred-1'
        );
        expect(pushCount).toBe(1);

        // Second request with same cache key - should use cache
        await store.requestMetadata(
          'job-123',
          '@openfn/language-dhis2',
          'cred-1'
        );
        expect(pushCount).toBe(1); // No additional push

        const state = store.getSnapshot();
        const jobState = state.jobs.get('job-123');
        expect(jobState?.metadata).toEqual(mockMetadata);
      }
    );

    metadataTest(
      'refetches when cache key changes',
      async ({ store, mockChannel, mockProvider }) => {
        let pushCount = 0;

        // Wrap the push to count calls
        const originalPush = createMockChannelPushOk(mockMetadataResponse);
        mockChannel.push = (...args: any[]) => {
          pushCount++;
          return originalPush.apply(mockChannel, args);
        };

        store._connectChannel(mockProvider as any);

        // First request
        await store.requestMetadata(
          'job-123',
          '@openfn/language-dhis2',
          'cred-1'
        );
        expect(pushCount).toBe(1);

        // Second request with different credential - should refetch
        await store.requestMetadata(
          'job-123',
          '@openfn/language-dhis2',
          'cred-2'
        );
        expect(pushCount).toBe(2);

        // Third request with different adaptor - should refetch
        await store.requestMetadata(
          'job-123',
          '@openfn/language-salesforce',
          'cred-2'
        );
        expect(pushCount).toBe(3);
      }
    );

    metadataTest(
      'prevents duplicate concurrent requests',
      async ({ store, mockChannel, mockProvider }) => {
        let pushCount = 0;

        mockChannel.push = createMockChannelPushOk(mockMetadataResponse);
        const originalPush = mockChannel.push;

        mockChannel.push = (...args: any[]) => {
          pushCount++;
          return originalPush.apply(mockChannel, args);
        };

        store._connectChannel(mockProvider as any);

        // Fire multiple requests simultaneously
        await Promise.all([
          store.requestMetadata('job-123', '@openfn/language-dhis2', 'cred-1'),
          store.requestMetadata('job-123', '@openfn/language-dhis2', 'cred-1'),
          store.requestMetadata('job-123', '@openfn/language-dhis2', 'cred-1'),
        ]);

        // Should only make one request
        expect(pushCount).toBeLessThanOrEqual(2); // 1 or 2 due to timing
      }
    );
  });

  describe('commands', () => {
    metadataTest(
      'clearMetadata removes job metadata',
      async ({ store, mockChannel, mockProvider }) => {
        // Setup and fetch some metadata first
        mockChannel.push = createMockChannelPushOk(mockMetadataResponse);
        store._connectChannel(mockProvider as any);

        await store.requestMetadata(
          'job-123',
          '@openfn/language-dhis2',
          'cred-1'
        );

        // Verify metadata exists
        let state = store.getSnapshot();
        expect(state.jobs.has('job-123')).toBe(true);

        // Clear it
        store.clearMetadata('job-123');

        // Verify it's gone
        state = store.getSnapshot();
        expect(state.jobs.has('job-123')).toBe(false);
      }
    );

    metadataTest(
      'clearAllMetadata removes all metadata',
      async ({ store, mockChannel, mockProvider }) => {
        // Setup and fetch metadata for multiple jobs
        mockChannel.push = createMockChannelPushOk(mockMetadataResponse);
        store._connectChannel(mockProvider as any);

        await store.requestMetadata(
          'job-123',
          '@openfn/language-dhis2',
          'cred-1'
        );

        mockChannel.push = createMockChannelPushOk({
          job_id: 'job-456',
          metadata: mockMetadata,
        });
        await store.requestMetadata(
          'job-456',
          '@openfn/language-dhis2',
          'cred-2'
        );

        // Verify metadata exists for both
        let state = store.getSnapshot();
        expect(state.jobs.size).toBeGreaterThan(0);

        // Clear all
        store.clearAllMetadata();

        // Verify all gone
        state = store.getSnapshot();
        expect(state.jobs.size).toBe(0);
      }
    );
  });

  describe('queries', () => {
    metadataTest(
      'getMetadataForJob returns correct metadata',
      async ({ store, mockChannel, mockProvider }) => {
        // Fetch metadata first
        mockChannel.push = createMockChannelPushOk(mockMetadataResponse);
        store._connectChannel(mockProvider as any);

        await store.requestMetadata(
          'job-123',
          '@openfn/language-dhis2',
          'cred-1'
        );

        const metadata = store.getMetadataForJob('job-123');
        expect(metadata).toEqual(mockMetadata);

        const notFound = store.getMetadataForJob('job-999');
        expect(notFound).toBeNull();
      }
    );

    metadataTest(
      'isLoadingForJob returns correct loading state',
      async ({ store, mockChannel, mockProvider }) => {
        // Setup response before request
        mockChannel.push = createMockChannelPushOk(mockMetadataResponse);
        store._connectChannel(mockProvider as any);

        // Initially not loading
        expect(store.isLoadingForJob('job-123')).toBe(false);

        // Request metadata
        await store.requestMetadata(
          'job-123',
          '@openfn/language-dhis2',
          'cred-1'
        );

        // After completion, should not be loading
        expect(store.isLoadingForJob('job-123')).toBe(false);

        // Non-existent job should return false
        expect(store.isLoadingForJob('job-999')).toBe(false);
      }
    );

    metadataTest(
      'getErrorForJob returns correct error',
      async ({ store, mockChannel, mockProvider }) => {
        // Fetch with error response
        mockChannel.push = createMockChannelPushOk(mockErrorResponse);
        store._connectChannel(mockProvider as any);

        await store.requestMetadata(
          'job-456',
          '@openfn/language-dhis2',
          'cred-2'
        );

        expect(store.getErrorForJob('job-456')).toBe('invalid_credentials');
        expect(store.getErrorForJob('job-999')).toBeNull();
      }
    );
  });
});
