/**
 * Tests for useAdaptors React hooks
 *
 * Tests the adaptor management hooks that provide convenient access
 * to adaptor functionality from React components using the StoreProvider context.
 */

import { act, renderHook, waitFor } from '@testing-library/react';
import type React from 'react';
import { describe, expect, test } from 'vitest';

import {
  useAdaptor,
  useAdaptorCommands,
  useAdaptors,
  useAdaptorsError,
  useAdaptorsInUse,
  useAdaptorsLoading,
} from '../../js/collaborative-editor/hooks/useAdaptors';
import { createSessionStore } from '../../js/collaborative-editor/stores/createSessionStore';

import { SessionContext } from '../../js/collaborative-editor/contexts/SessionProvider';
import { StoreContext } from '../../js/collaborative-editor/contexts/StoreProvider';
import { createAdaptorStore } from '../../js/collaborative-editor/stores/createAdaptorStore';
import { createAwarenessStore } from '../../js/collaborative-editor/stores/createAwarenessStore';
import { createCredentialStore } from '../../js/collaborative-editor/stores/createCredentialStore';
import { createSessionContextStore } from '../../js/collaborative-editor/stores/createSessionContextStore';
import { createWorkflowStore } from '../../js/collaborative-editor/stores/createWorkflowStore';
import {
  mockAdaptorsList,
  mockAdaptor,
  mockAdaptorGmail,
  mockAdaptorCommon,
} from './fixtures/adaptorData';
import { createMockSocket } from './mocks/phoenixSocket';

// =============================================================================
// TEST HELPERS
// =============================================================================

function createWrapper() {
  const sessionStore = createSessionStore();
  const adaptorStore = createAdaptorStore();
  const credentialStore = createCredentialStore();
  const awarenessStore = createAwarenessStore();
  const workflowStore = createWorkflowStore();
  const sessionContextStore = createSessionContextStore();

  const mockSocket = createMockSocket();

  sessionStore.initializeSession(mockSocket, 'test:room', {
    id: 'user-1',
    name: 'Test User',
    color: '#ff0000',
  });

  const stores = {
    adaptorStore,
    credentialStore,
    awarenessStore,
    workflowStore,
    sessionContextStore,
  };

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={sessionStore}>
      <StoreContext.Provider value={stores}>{children}</StoreContext.Provider>
    </SessionContext.Provider>
  );

  return { wrapper, stores, sessionStore };
}

describe('useAdaptors hooks', () => {
  describe('context validation', () => {
    test('all hooks require StoreProvider context', () => {
      expect(() => renderHook(() => useAdaptors())).toThrow(
        'useAdaptorStore must be used within a StoreProvider'
      );
      expect(() => renderHook(() => useAdaptorsLoading())).toThrow(
        'useAdaptorStore must be used within a StoreProvider'
      );
      expect(() => renderHook(() => useAdaptorsError())).toThrow(
        'useAdaptorStore must be used within a StoreProvider'
      );
      expect(() => renderHook(() => useAdaptorCommands())).toThrow(
        'useAdaptorStore must be used within a StoreProvider'
      );
      expect(() =>
        renderHook(() => useAdaptor('@openfn/language-http'))
      ).toThrow('useAdaptorStore must be used within a StoreProvider');
    });
  });

  describe('useAdaptors', () => {
    test('returns adaptors and updates when store changes', async () => {
      const { wrapper, stores } = createWrapper();
      const { result } = renderHook(() => useAdaptors(), { wrapper });

      expect(result.current).toEqual([]);
      expect(Array.isArray(result.current)).toBe(true);

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      await waitFor(() => {
        expect(result.current).toHaveLength(3);
      });
    });

    test('only re-renders when adaptors change, not other state', async () => {
      const { wrapper, stores } = createWrapper();
      let renderCount = 0;

      const { result } = renderHook(
        () => {
          renderCount++;
          return useAdaptors();
        },
        { wrapper }
      );

      const initialRenderCount = renderCount;

      act(() => {
        stores.adaptorStore.setLoading(true);
        stores.adaptorStore.setError('Test error');
      });

      expect(renderCount).toBe(initialRenderCount);

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      await waitFor(() => {
        expect(renderCount).toBeGreaterThan(initialRenderCount);
        expect(result.current).toHaveLength(3);
      });
    });
  });

  describe('useAdaptorsLoading', () => {
    test('returns loading state and updates', async () => {
      const { wrapper, stores } = createWrapper();
      const { result } = renderHook(() => useAdaptorsLoading(), { wrapper });

      expect(result.current).toBe(false);
      expect(typeof result.current).toBe('boolean');

      act(() => {
        stores.adaptorStore.setLoading(true);
      });

      await waitFor(() => {
        expect(result.current).toBe(true);
      });

      act(() => {
        stores.adaptorStore.setLoading(false);
      });

      await waitFor(() => {
        expect(result.current).toBe(false);
      });
    });
  });

  describe('useAdaptorsError', () => {
    test('tracks error state lifecycle', async () => {
      const { wrapper, stores } = createWrapper();
      const { result } = renderHook(() => useAdaptorsError(), { wrapper });

      expect(result.current).toBe(null);

      act(() => {
        stores.adaptorStore.setError('Error 1');
      });

      await waitFor(() => {
        expect(result.current).toBe('Error 1');
      });

      act(() => {
        stores.adaptorStore.setError('Error 2');
      });

      await waitFor(() => {
        expect(result.current).toBe('Error 2');
      });

      act(() => {
        stores.adaptorStore.clearError();
      });

      await waitFor(() => {
        expect(result.current).toBe(null);
      });
    });
  });

  describe('useAdaptorCommands', () => {
    test('provides stable command functions', () => {
      const { wrapper } = createWrapper();
      const { result, rerender } = renderHook(() => useAdaptorCommands(), {
        wrapper,
      });

      expect(result.current).toHaveProperty('requestAdaptors');
      expect(result.current).toHaveProperty('setAdaptors');
      expect(result.current).toHaveProperty('clearError');

      const commands1 = result.current;
      rerender();
      const commands2 = result.current;

      expect(commands1.requestAdaptors).toBe(commands2.requestAdaptors);
      expect(commands1.setAdaptors).toBe(commands2.setAdaptors);
      expect(commands1.clearError).toBe(commands2.clearError);
    });

    test("commands work and don't re-render on state changes", async () => {
      const { wrapper, stores } = createWrapper();
      let renderCount = 0;

      const { result: commands } = renderHook(
        () => {
          renderCount++;
          return useAdaptorCommands();
        },
        { wrapper }
      );

      const { result: adaptors } = renderHook(() => useAdaptors(), {
        wrapper,
      });

      const { result: error } = renderHook(() => useAdaptorsError(), {
        wrapper,
      });

      const initialRenderCount = renderCount;

      act(() => {
        commands.current.setAdaptors(mockAdaptorsList);
      });

      await waitFor(() => {
        expect(adaptors.current).toHaveLength(3);
      });

      act(() => {
        stores.adaptorStore.setError('Test error');
      });

      await waitFor(() => {
        expect(error.current).toBe('Test error');
      });

      act(() => {
        commands.current.clearError();
      });

      await waitFor(() => {
        expect(error.current).toBe(null);
      });

      expect(renderCount).toBe(initialRenderCount);
    });
  });

  describe('useAdaptor', () => {
    test('finds adaptor by name and returns null for non-existent', async () => {
      const { wrapper, stores } = createWrapper();

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      const { result: httpAdaptor } = renderHook(
        () => useAdaptor('@openfn/language-http'),
        { wrapper }
      );

      const { result: nonExistent } = renderHook(
        () => useAdaptor('@openfn/nonexistent'),
        { wrapper }
      );

      await waitFor(() => {
        expect(httpAdaptor.current).not.toBe(null);
        expect(httpAdaptor.current?.name).toBe('@openfn/language-http');
        expect(httpAdaptor.current?.latest).toBe('2.1.0');
      });

      expect(nonExistent.current).toBe(null);
    });

    test('updates when adaptors change or search name changes', async () => {
      const { wrapper, stores } = createWrapper();
      const { result } = renderHook(() => useAdaptor('@openfn/language-http'), {
        wrapper,
      });

      expect(result.current).toBe(null);

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      await waitFor(() => {
        expect(result.current?.name).toBe('@openfn/language-http');
      });
    });

    test('supports searching for different adaptors', async () => {
      const { wrapper, stores } = createWrapper();

      act(() => {
        stores.adaptorStore.setAdaptors(mockAdaptorsList);
      });

      const { result, rerender } = renderHook(({ name }) => useAdaptor(name), {
        wrapper,
        initialProps: { name: '@openfn/language-http' },
      });

      await waitFor(() => {
        expect(result.current?.name).toBe('@openfn/language-http');
      });

      rerender({ name: '@openfn/language-dhis2' });

      await waitFor(() => {
        expect(result.current?.name).toBe('@openfn/language-dhis2');
      });
    });
  });

  describe('selective subscriptions', () => {
    test('hooks with different selectors update independently', async () => {
      const { wrapper, stores } = createWrapper();

      let adaptorsRenderCount = 0;
      let loadingRenderCount = 0;

      renderHook(
        () => {
          adaptorsRenderCount++;
          return useAdaptors();
        },
        { wrapper }
      );

      renderHook(
        () => {
          loadingRenderCount++;
          return useAdaptorsLoading();
        },
        { wrapper }
      );

      const initialAdaptorsCount = adaptorsRenderCount;
      const initialLoadingCount = loadingRenderCount;

      act(() => {
        stores.adaptorStore.setLoading(true);
      });

      await waitFor(() => {
        expect(loadingRenderCount).toBeGreaterThan(initialLoadingCount);
      });

      expect(adaptorsRenderCount).toBe(initialAdaptorsCount);
    });
  });

  describe('useAdaptorsInUse', () => {
    test('requires StoreProvider context', () => {
      expect(() => renderHook(() => useAdaptorsInUse())).toThrow(
        'useAdaptorsInUse must be used within a StoreProvider'
      );
    });

    test('derives adaptors in use from Y.Doc jobs', async () => {
      const { wrapper, stores } = createWrapper();
      const { result } = renderHook(() => useAdaptorsInUse(), { wrapper });

      const allAdaptors = [mockAdaptor, mockAdaptorGmail, mockAdaptorCommon];
      act(() => {
        stores.adaptorStore.setAdaptors(allAdaptors);
      });

      act(() => {
        stores.workflowStore._setJobsForTesting([
          {
            id: 'job-1',
            name: 'HTTP Job',
            adaptor: '@openfn/language-http@2.1.0',
            body: '',
          },
          {
            id: 'job-2',
            name: 'Common Job',
            adaptor: '@openfn/language-common@2.0.0',
            body: '',
          },
        ]);
      });

      await waitFor(() => {
        expect(result.current.adaptorsInUse).toHaveLength(2);
      });

      const names = result.current.adaptorsInUse.map(a => a.name);
      expect(names).toEqual([
        '@openfn/language-common',
        '@openfn/language-http',
      ]);

      // Per-entry referential identity: each item in adaptorsInUse is the same
      // reference as the corresponding catalogue entry.
      const catalogue = result.current.allAdaptors;
      for (const a of result.current.adaptorsInUse) {
        const fromCatalogue = catalogue.find(c => c.name === a.name);
        expect(a).toBe(fromCatalogue);
      }
    });

    test('returns empty list when workflow has no jobs', async () => {
      const { wrapper, stores } = createWrapper();
      const { result } = renderHook(() => useAdaptorsInUse(), { wrapper });

      const allAdaptors = [mockAdaptor, mockAdaptorGmail, mockAdaptorCommon];
      act(() => {
        stores.adaptorStore.setAdaptors(allAdaptors);
      });

      await waitFor(() => {
        expect(result.current.allAdaptors).toHaveLength(3);
      });

      expect(result.current.adaptorsInUse).toEqual([]);
    });

    test('ignores jobs referencing adaptors absent from the catalogue', async () => {
      const { wrapper, stores } = createWrapper();
      const { result } = renderHook(() => useAdaptorsInUse(), { wrapper });

      act(() => {
        stores.adaptorStore.setAdaptors([mockAdaptor]);
      });

      act(() => {
        stores.workflowStore._setJobsForTesting([
          {
            id: 'job-1',
            name: 'Unknown',
            adaptor: '@openfn/language-unknown@1.0.0',
            body: '',
          },
          {
            id: 'job-2',
            name: 'HTTP',
            adaptor: '@openfn/language-http@2.0.0',
            body: '',
          },
        ]);
      });

      await waitFor(() => {
        expect(result.current.adaptorsInUse).toHaveLength(1);
      });

      expect(result.current.adaptorsInUse[0]?.name).toBe(
        '@openfn/language-http'
      );
    });

    test('matches version-suffixed adaptor specs against catalogue package names', async () => {
      const { wrapper, stores } = createWrapper();
      const { result } = renderHook(() => useAdaptorsInUse(), { wrapper });

      act(() => {
        stores.adaptorStore.setAdaptors([mockAdaptor]);
      });

      act(() => {
        stores.workflowStore._setJobsForTesting([
          {
            id: 'job-1',
            name: 'HTTP',
            adaptor: '@openfn/language-http@2.0.0',
            body: '',
          },
        ]);
      });

      await waitFor(() => {
        expect(result.current.adaptorsInUse.map(a => a.name)).toEqual([
          '@openfn/language-http',
        ]);
      });
    });
  });
});
