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
  useAdaptorsLoading,
  useProjectAdaptors,
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

  describe('useProjectAdaptors', () => {
    test('requires StoreProvider context', () => {
      expect(() => renderHook(() => useProjectAdaptors())).toThrow(
        'useProjectAdaptors must be used within a StoreProvider'
      );
    });

    test('returns projectAdaptors, allAdaptors, and isLoading', async () => {
      const { wrapper, stores } = createWrapper();
      const { result } = renderHook(() => useProjectAdaptors(), { wrapper });

      // Initially empty
      expect(result.current.projectAdaptors).toEqual([]);
      expect(result.current.allAdaptors).toEqual([]);
      expect(result.current.isLoading).toBe(false);

      // Set all adaptors (simulates backend response)
      const allAdaptors = [mockAdaptor, mockAdaptorGmail, mockAdaptorCommon];
      act(() => {
        stores.adaptorStore.setAdaptors(allAdaptors);
      });

      await waitFor(() => {
        expect(result.current.allAdaptors).toHaveLength(3);
      });
    });

    test('merges Y.Doc job adaptors into projectAdaptors', async () => {
      const { wrapper, stores } = createWrapper();
      const { result } = renderHook(() => useProjectAdaptors(), { wrapper });

      // Set all available adaptors
      const allAdaptors = [mockAdaptor, mockAdaptorGmail, mockAdaptorCommon];
      act(() => {
        stores.adaptorStore.setAdaptors(allAdaptors);
      });

      // Add a job to the workflow store that uses Gmail adaptor
      act(() => {
        stores.workflowStore._setJobsForTesting([
          {
            id: 'job-1',
            name: 'Test Job',
            adaptor: '@openfn/language-gmail@latest',
            body: 'fn(state => state)',
          },
        ]);
      });

      // projectAdaptors should now include Gmail from Y.Doc
      await waitFor(() => {
        const projectAdaptorNames = result.current.projectAdaptors.map(
          a => a.name
        );
        expect(projectAdaptorNames).toContain('@openfn/language-gmail');
      });
    });

    test('does not duplicate adaptors already in backend projectAdaptors', async () => {
      const { wrapper, stores } = createWrapper();
      const { result } = renderHook(() => useProjectAdaptors(), { wrapper });

      // Set all available adaptors and project adaptors (simulates backend where HTTP is already saved)
      const allAdaptors = [mockAdaptor, mockAdaptorGmail, mockAdaptorCommon];
      act(() => {
        stores.adaptorStore.setAdaptors(allAdaptors);
        // Directly set projectAdaptors via internal state modification
        stores.adaptorStore._setProjectAdaptors([mockAdaptor]);
      });

      // Add a job that uses HTTP (already in projectAdaptors from backend)
      act(() => {
        stores.workflowStore._setJobsForTesting([
          {
            id: 'job-1',
            name: 'Test Job',
            adaptor: '@openfn/language-http@2.1.0',
            body: 'fn(state => state)',
          },
        ]);
      });

      await waitFor(() => {
        // Should only have HTTP once, not duplicated
        const httpCount = result.current.projectAdaptors.filter(
          a => a.name === '@openfn/language-http'
        ).length;
        expect(httpCount).toBe(1);
      });
    });

    test('handles jobs without adaptor field', async () => {
      const { wrapper, stores } = createWrapper();
      const { result } = renderHook(() => useProjectAdaptors(), { wrapper });

      // Set all available adaptors
      const allAdaptors = [mockAdaptor, mockAdaptorGmail];
      act(() => {
        stores.adaptorStore.setAdaptors(allAdaptors);
      });

      // Add a job without an adaptor field (should not crash)
      act(() => {
        stores.workflowStore._setJobsForTesting([
          {
            id: 'job-1',
            name: 'Test Job',
            adaptor: undefined as any,
            body: 'fn(state => state)',
          },
        ]);
      });

      // Should not throw and projectAdaptors should be empty (no backend project adaptors set)
      await waitFor(() => {
        expect(result.current.projectAdaptors).toEqual([]);
      });
    });

    test('sorts merged projectAdaptors alphabetically', async () => {
      const { wrapper, stores } = createWrapper();
      const { result } = renderHook(() => useProjectAdaptors(), { wrapper });

      // Set all available adaptors
      const allAdaptors = [mockAdaptor, mockAdaptorGmail, mockAdaptorCommon];
      act(() => {
        stores.adaptorStore.setAdaptors(allAdaptors);
        // Set HTTP as already in project from backend
        stores.adaptorStore._setProjectAdaptors([mockAdaptor]);
      });

      // Add jobs using Gmail and Common (not in backend projectAdaptors)
      act(() => {
        stores.workflowStore._setJobsForTesting([
          {
            id: 'job-1',
            name: 'Gmail Job',
            adaptor: '@openfn/language-gmail@latest',
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
        expect(result.current.projectAdaptors).toHaveLength(3);
        const names = result.current.projectAdaptors.map(a => a.name);
        // Should be sorted: common, gmail, http
        expect(names).toEqual([
          '@openfn/language-common',
          '@openfn/language-gmail',
          '@openfn/language-http',
        ]);
      });
    });
  });
});
