/**
 * Integration tests for useValidation hook
 *
 * These tests use real WorkflowStore instances to verify the full error flow
 * through Y.Doc and Immer state, ensuring that store API changes are caught.
 *
 * Unlike useValidation.test.tsx which mocks useWorkflowState/useWorkflowActions,
 * these tests use the real implementations to verify end-to-end integration.
 */

import { renderHook, waitFor } from '@testing-library/react';
import type React from 'react';
import { act } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { StoreContext } from '#/collaborative-editor/contexts/StoreProvider';
import { useValidation } from '#/collaborative-editor/hooks/useValidation';
import {
  createMinimalWorkflowYDoc,
  createWorkflowYDoc,
  setupWorkflowStoreTest,
} from '../__helpers__';

describe('useValidation - Integration', () => {
  let mockForm: any;
  let subscribeCallbacks: Array<() => void>;

  beforeEach(() => {
    subscribeCallbacks = [];

    mockForm = {
      state: {
        values: { name: '', body: '' },
        fieldMeta: {},
      },
      store: {
        subscribe: vi.fn((callback: () => void) => {
          subscribeCallbacks.push(callback);
          return vi.fn(); // Unsubscribe function
        }),
      },
      getFieldMeta: vi.fn((fieldName: string) => {
        return mockForm.state.fieldMeta[fieldName] || {};
      }),
      setFieldMeta: vi.fn((fieldName: string, updater: (old: any) => any) => {
        const oldMeta = mockForm.state.fieldMeta[fieldName] || {};
        mockForm.state.fieldMeta[fieldName] = updater(oldMeta);
      }),
    };
  });

  function createIntegrationWrapper(
    workflowStore: any
  ): React.ComponentType<{ children: React.ReactNode }> {
    const mockStoreValue = {
      workflowStore,
      sessionContextStore: {} as any,
      adaptorStore: {} as any,
      credentialStore: {} as any,
      awarenessStore: {} as any,
    };

    return ({ children }: { children: React.ReactNode }) => (
      <StoreContext.Provider value={mockStoreValue}>
        {children}
      </StoreContext.Provider>
    );
  }

  it('should read Y.Doc errors and inject into form errorMap', async () => {
    const { store, ydoc, cleanup } = setupWorkflowStoreTest(
      createMinimalWorkflowYDoc()
    );

    const wrapper = createIntegrationWrapper(store);

    renderHook(() => useValidation(mockForm), { wrapper });

    // Set error in Y.Doc
    act(() => {
      ydoc.transact(() => {
        const errorsMap = ydoc.getMap('errors');
        errorsMap.set('workflow', { name: ['Name is required'] });
      });
    });

    // Wait for store observer to update Immer state and form to receive error
    await waitFor(() => {
      const calls = mockForm.setFieldMeta.mock.calls.filter(
        (call: any) => call[0] === 'name'
      );
      expect(calls.length).toBeGreaterThan(0);

      const updaterFn = calls[0][1];
      const result = updaterFn({});
      expect(result.errorMap.collaborative).toBe('Name is required');
    });

    cleanup();
  });

  it('should write client errors to Y.Doc (debounced)', async () => {
    const { store, ydoc, cleanup } = setupWorkflowStoreTest(
      createMinimalWorkflowYDoc()
    );

    const wrapper = createIntegrationWrapper(store);

    renderHook(() => useValidation(mockForm), { wrapper });

    // Simulate form validation error
    mockForm.state.fieldMeta.name = {
      errors: ['Name is too short'],
      isTouched: true,
    };
    mockForm.getFieldMeta.mockImplementation((fieldName: string) => {
      if (fieldName === 'name') {
        return { errors: ['Name is too short'], isTouched: true };
      }
      return null;
    });

    // Trigger form subscription
    act(() => {
      subscribeCallbacks.forEach(cb => cb());
    });

    // Wait for debounced write (500ms) + Y.Doc update
    await waitFor(
      () => {
        const errorsMap = ydoc.getMap('errors');
        const workflowErrors = errorsMap.get('workflow') as Record<
          string,
          string[]
        >;
        expect(workflowErrors).toEqual({ name: ['Name is too short'] });
      },
      { timeout: 1000 }
    );

    cleanup();
  });

  it('should preserve errors during entity property updates', async () => {
    // Create workflow with a job
    const ydocWithJob = createWorkflowYDoc({
      jobs: {
        'job-123': {
          id: 'job-123',
          name: 'Test Job',
          adaptor: '@openfn/language-common',
        },
      },
    });

    const { store, ydoc, cleanup } = setupWorkflowStoreTest(ydocWithJob);

    const wrapper = createIntegrationWrapper(store);

    // Use errorPath for job-specific errors
    renderHook(() => useValidation(mockForm, 'jobs.job-123'), { wrapper });

    // Set error in Y.Doc for job body field
    act(() => {
      ydoc.transact(() => {
        const errorsMap = ydoc.getMap('errors');
        errorsMap.set('jobs', { 'job-123': { body: ['Body is required'] } });
      });
    });

    // Wait for error to propagate
    await waitFor(() => {
      const calls = mockForm.setFieldMeta.mock.calls.filter(
        (call: any) => call[0] === 'body'
      );
      expect(calls.length).toBeGreaterThan(0);
    });

    // Update job name (should preserve error)
    act(() => {
      ydoc.transact(() => {
        const jobsArray = ydoc.getArray('jobs');
        const jobMap = jobsArray.get(0) as any;
        jobMap.set('name', 'Updated Job Name');
      });
    });

    // Verify error is still present after property update
    await waitFor(() => {
      const errorsMap = ydoc.getMap('errors');
      const jobsErrors = errorsMap.get('jobs') as Record<
        string,
        Record<string, string[]>
      >;
      expect(jobsErrors['job-123'].body).toEqual(['Body is required']);
    });

    cleanup();
  });

  it('should clear errors from Y.Doc when client sends empty array', async () => {
    const { store, ydoc, cleanup } = setupWorkflowStoreTest(
      createMinimalWorkflowYDoc()
    );

    const wrapper = createIntegrationWrapper(store);

    // Set initial error in Y.Doc
    act(() => {
      ydoc.transact(() => {
        const errorsMap = ydoc.getMap('errors');
        errorsMap.set('workflow', { name: ['Name is required'] });
      });
    });

    renderHook(() => useValidation(mockForm), { wrapper });

    // Wait for initial error to be read
    await waitFor(() => {
      const calls = mockForm.setFieldMeta.mock.calls.filter(
        (call: any) => call[0] === 'name'
      );
      expect(calls.length).toBeGreaterThan(0);
    });

    // Now simulate field becoming valid (empty errors array)
    mockForm.state.fieldMeta.name = { errors: [], isTouched: true };
    mockForm.getFieldMeta.mockImplementation((fieldName: string) => {
      if (fieldName === 'name') {
        return { errors: [], isTouched: true };
      }
      return null;
    });

    // Trigger subscription
    act(() => {
      subscribeCallbacks.forEach(cb => cb());
    });

    // Wait for debounced write + Y.Doc clear
    await waitFor(
      () => {
        const errorsMap = ydoc.getMap('errors');
        const workflowErrors = errorsMap.get('workflow') as
          | Record<string, string[]>
          | undefined;
        // Error should be cleared
        expect(workflowErrors?.name).toBeUndefined();
      },
      { timeout: 1000 }
    );

    cleanup();
  });
});
