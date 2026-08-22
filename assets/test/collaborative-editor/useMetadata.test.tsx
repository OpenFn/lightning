/**
 * Minimal test suite for useMetadata hook
 *
 * Tests the React hook integration with the metadata store
 */

import { describe, test, expect, beforeEach, vi } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import type { ReactNode } from 'react';

import { useMetadata } from '../../js/collaborative-editor/hooks/useMetadata';
import { createMetadataStore } from '../../js/collaborative-editor/stores/createMetadataStore';
import { StoreContext } from '../../js/collaborative-editor/contexts/StoreProvider';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from './mocks/phoenixChannel';
import { createMockChannelPushOk } from './__helpers__/channelMocks';

// Mock useCurrentJob hook
vi.mock('../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useCurrentJob: vi.fn(),
}));

import { useCurrentJob } from '../../js/collaborative-editor/hooks/useWorkflow';

const mockMetadata = {
  dataElements: [{ id: 'de1', name: 'Element 1' }],
};

describe('useMetadata', () => {
  let metadataStore: ReturnType<typeof createMetadataStore>;
  let mockChannel: ReturnType<typeof createMockPhoenixChannel>;

  beforeEach(() => {
    metadataStore = createMetadataStore();
    mockChannel = createMockPhoenixChannel();
    const mockProvider = createMockPhoenixChannelProvider(mockChannel);

    // Connect store to channel
    metadataStore._connectChannel(mockProvider as any);

    // Reset mock
    vi.clearAllMocks();
  });

  const wrapper = ({ children }: { children: ReactNode }) => (
    <StoreContext.Provider
      value={{
        metadataStore,
        adaptorStore: {} as any,
        credentialStore: {} as any,
        awarenessStore: {} as any,
        workflowStore: {} as any,
        sessionContextStore: {} as any,
        historyStore: {} as any,
        uiStore: {} as any,
        editorPreferencesStore: {} as any,
        aiAssistantStore: {} as any,
      }}
    >
      {children}
    </StoreContext.Provider>
  );

  test('returns null metadata when no job is selected', () => {
    vi.mocked(useCurrentJob).mockReturnValue({
      job: null,
      ytext: null,
    });

    const { result } = renderHook(() => useMetadata(), { wrapper });

    expect(result.current.metadata).toBeNull();
    expect(result.current.isLoading).toBe(false);
    expect(result.current.error).toBeNull();
    expect(result.current.refetch).toBeUndefined();
  });

  test('auto-fetches metadata when job is selected', async () => {
    const mockJob = {
      id: 'job-123',
      adaptor: '@openfn/language-dhis2@6.0.0',
      project_credential_id: 'cred-1',
      keychain_credential_id: null,
    };

    vi.mocked(useCurrentJob).mockReturnValue({
      job: mockJob as any,
      ytext: {} as any,
    });

    // Setup mock response
    mockChannel.push = createMockChannelPushOk({
      job_id: 'job-123',
      metadata: mockMetadata,
    });

    const { result } = renderHook(() => useMetadata(), { wrapper });

    // Initially loading or empty
    expect(result.current.metadata).toBeNull();

    // Wait for metadata to be fetched
    await waitFor(
      () => {
        expect(result.current.metadata).toEqual(mockMetadata);
      },
      { timeout: 1000 }
    );

    expect(result.current.isLoading).toBe(false);
    expect(result.current.error).toBeNull();
  });

  test('provides refetch function when job is selected', () => {
    const mockJob = {
      id: 'job-123',
      adaptor: '@openfn/language-dhis2@6.0.0',
      project_credential_id: 'cred-1',
      keychain_credential_id: null,
    };

    vi.mocked(useCurrentJob).mockReturnValue({
      job: mockJob as any,
      ytext: {} as any,
    });

    const { result } = renderHook(() => useMetadata(), { wrapper });

    expect(result.current.refetch).toBeDefined();
    expect(typeof result.current.refetch).toBe('function');
  });

  test('handles metadata errors', async () => {
    const mockJob = {
      id: 'job-456',
      adaptor: '@openfn/language-dhis2@6.0.0',
      project_credential_id: 'cred-2',
      keychain_credential_id: null,
    };

    vi.mocked(useCurrentJob).mockReturnValue({
      job: mockJob as any,
      ytext: {} as any,
    });

    // Setup error response
    mockChannel.push = createMockChannelPushOk({
      job_id: 'job-456',
      metadata: { error: 'invalid_credentials' },
    });

    const { result } = renderHook(() => useMetadata(), { wrapper });

    // Wait for error to be set
    await waitFor(
      () => {
        expect(result.current.error).toBe('invalid_credentials');
      },
      { timeout: 1000 }
    );

    expect(result.current.metadata).toBeNull();
    expect(result.current.isLoading).toBe(false);
  });

  test('refetches when job adaptor changes', async () => {
    const mockJob1 = {
      id: 'job-123',
      adaptor: '@openfn/language-dhis2@6.0.0',
      project_credential_id: 'cred-1',
      keychain_credential_id: null,
    };

    vi.mocked(useCurrentJob).mockReturnValue({
      job: mockJob1 as any,
      ytext: {} as any,
    });

    mockChannel.push = createMockChannelPushOk({
      job_id: 'job-123',
      metadata: mockMetadata,
    });

    const { result, rerender } = renderHook(() => useMetadata(), { wrapper });

    // Wait for initial fetch
    await waitFor(() => {
      expect(result.current.metadata).toEqual(mockMetadata);
    });

    // Change adaptor
    const mockJob2 = {
      ...mockJob1,
      adaptor: '@openfn/language-salesforce@6.0.0',
    };

    vi.mocked(useCurrentJob).mockReturnValue({
      job: mockJob2 as any,
      ytext: {} as any,
    });

    const newMetadata = { objects: [{ name: 'Account' }] };
    mockChannel.push = createMockChannelPushOk({
      job_id: 'job-123',
      metadata: newMetadata,
    });

    rerender();

    // Should refetch with new adaptor
    await waitFor(() => {
      expect(result.current.metadata).toEqual(newMetadata);
    });
  });

  test('refetches when credential changes', async () => {
    const mockJob1 = {
      id: 'job-123',
      adaptor: '@openfn/language-dhis2@6.0.0',
      project_credential_id: 'cred-1',
      keychain_credential_id: null,
    };

    vi.mocked(useCurrentJob).mockReturnValue({
      job: mockJob1 as any,
      ytext: {} as any,
    });

    mockChannel.push = createMockChannelPushOk({
      job_id: 'job-123',
      metadata: mockMetadata,
    });

    const { result, rerender } = renderHook(() => useMetadata(), { wrapper });

    await waitFor(() => {
      expect(result.current.metadata).toEqual(mockMetadata);
    });

    // Change credential
    const mockJob2 = {
      ...mockJob1,
      project_credential_id: 'cred-2',
    };

    vi.mocked(useCurrentJob).mockReturnValue({
      job: mockJob2 as any,
      ytext: {} as any,
    });

    const newMetadata = { dataElements: [{ id: 'de2', name: 'Element 2' }] };
    mockChannel.push = createMockChannelPushOk({
      job_id: 'job-123',
      metadata: newMetadata,
    });

    rerender();

    await waitFor(() => {
      expect(result.current.metadata).toEqual(newMetadata);
    });
  });
});
