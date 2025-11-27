import { renderHook, waitFor } from '@testing-library/react';
import { act } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useValidation } from '#/collaborative-editor/hooks/useValidation';
import * as useWorkflowModule from '#/collaborative-editor/hooks/useWorkflow';

// Mock dependencies
vi.mock('#/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowState: vi.fn(),
  useWorkflowActions: vi.fn(),
}));

/**
 * Test suite for useValidation hook
 *
 * Tests the unified collaborative validation system that handles both
 * server-side (Ecto) and client-side (TanStack Form/Zod) validation errors.
 *
 * Note: Integration tests using real WorkflowStore are in
 * useValidation.integration.test.tsx to avoid mock conflicts.
 */
describe('useValidation', () => {
  let mockForm: any;
  let mockSetClientErrors: any;
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

    mockSetClientErrors = vi.fn();

    // Setup default mocks
    vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
      (selector: any) =>
        selector({
          workflow: { errors: {} },
          jobs: [],
          triggers: [],
          edges: [],
        })
    );
    vi.mocked(useWorkflowModule.useWorkflowActions).mockReturnValue({
      setClientErrors: mockSetClientErrors,
    } as any);
  });

  describe('reading errors from workflow state', () => {
    it('should read errors from workflow-level state', () => {
      vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
        (selector: any) =>
          selector({
            workflow: { errors: { name: ['Name is required'] } },
            jobs: [],
            triggers: [],
            edges: [],
          })
      );

      renderHook(() => useValidation(mockForm));

      // Hook should inject collaborative errors into form
      expect(mockForm.setFieldMeta).toHaveBeenCalled();
    });

    it('should read errors from entity state when errorPath provided', () => {
      const mockJob = {
        id: 'job-123',
        errors: { body: ['Body is required'] },
      };
      vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
        (selector: any) =>
          selector({
            workflow: {},
            jobs: [mockJob],
            triggers: [],
            edges: [],
          })
      );

      renderHook(() => useValidation(mockForm, 'jobs.job-123'));

      // Selector should be called to extract job errors
      expect(useWorkflowModule.useWorkflowState).toHaveBeenCalled();
    });

    it('should handle missing entity gracefully', () => {
      vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
        (selector: any) =>
          selector({
            workflow: {},
            jobs: [],
            triggers: [],
            edges: [],
          })
      );

      // Should not throw when entity doesn't exist
      expect(() => {
        renderHook(() => useValidation(mockForm, 'jobs.nonexistent'));
      }).not.toThrow();
    });

    it('should handle invalid entity type gracefully', () => {
      vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
        (selector: any) =>
          selector({
            workflow: {},
            jobs: [],
            triggers: [],
            edges: [],
          })
      );

      // Should not throw with invalid path
      expect(() => {
        renderHook(() => useValidation(mockForm, 'invalid.path'));
      }).not.toThrow();
    });
  });

  describe('injecting collaborative errors into form fields', () => {
    it('should inject collaborative errors into form errorMap', async () => {
      vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
        (selector: any) =>
          selector({
            workflow: { errors: { name: ['Name is required'] } },
            jobs: [],
            triggers: [],
            edges: [],
          })
      );

      renderHook(() => useValidation(mockForm));

      await waitFor(() => {
        // Should set errorMap with collaborative error
        const calls = mockForm.setFieldMeta.mock.calls.filter(
          (call: any) => call[0] === 'name'
        );
        expect(calls.length).toBeGreaterThan(0);

        // Get the updater function and call it to verify behavior
        const updaterFn = calls[0][1];
        const result = updaterFn({});
        expect(result.errorMap.collaborative).toBe('Name is required');
      });
    });

    it('should handle multiple fields with errors', async () => {
      vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
        (selector: any) =>
          selector({
            workflow: {
              errors: {
                name: ['Name is required'],
                body: ['Body is too short'],
              },
            },
            jobs: [],
            triggers: [],
            edges: [],
          })
      );

      renderHook(() => useValidation(mockForm));

      await waitFor(() => {
        // Both fields should have collaborative errors set
        expect(
          mockForm.setFieldMeta.mock.calls.some(
            (call: any) => call[0] === 'name'
          )
        ).toBe(true);
        expect(
          mockForm.setFieldMeta.mock.calls.some(
            (call: any) => call[0] === 'body'
          )
        ).toBe(true);
      });
    });

    it('should use first error message from array', async () => {
      vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
        (selector: any) =>
          selector({
            workflow: {
              errors: {
                name: ['First error', 'Second error', 'Third error'],
              },
            },
            jobs: [],
            triggers: [],
            edges: [],
          })
      );

      renderHook(() => useValidation(mockForm));

      await waitFor(() => {
        const calls = mockForm.setFieldMeta.mock.calls.filter(
          (call: any) => call[0] === 'name'
        );
        const updaterFn = calls[0][1];
        const result = updaterFn({});
        expect(result.errorMap.collaborative).toBe('First error');
      });
    });

    it('should clear collaborative errors when no errors in state', async () => {
      // Start with errors
      vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
        (selector: any) =>
          selector({
            workflow: { errors: { name: ['Name is required'] } },
            jobs: [],
            triggers: [],
            edges: [],
          })
      );

      const { rerender } = renderHook(() => useValidation(mockForm));

      await waitFor(() => {
        expect(mockForm.setFieldMeta).toHaveBeenCalled();
      });

      // Clear errors
      vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
        (selector: any) =>
          selector({
            workflow: { errors: {} },
            jobs: [],
            triggers: [],
            edges: [],
          })
      );

      mockForm.setFieldMeta.mockClear();
      rerender();

      await waitFor(() => {
        // Should clear the collaborative error
        const calls = mockForm.setFieldMeta.mock.calls.filter(
          (call: any) => call[0] === 'name'
        );
        if (calls.length > 0) {
          const updaterFn = calls[0][1];
          const result = updaterFn({
            errorMap: { collaborative: 'old error' },
          });
          expect(result.errorMap.collaborative).toBeUndefined();
        }
      });
    });
  });

  describe('writing client validation errors to Y.Doc', () => {
    it('should write form validation errors to Y.Doc (debounced)', async () => {
      renderHook(() => useValidation(mockForm));

      // Simulate form validation error on name field only
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

      // Trigger form subscription callback
      act(() => {
        subscribeCallbacks.forEach(cb => cb());
      });

      // Wait for debounced write (500ms)
      await waitFor(
        () => {
          expect(mockSetClientErrors).toHaveBeenCalledWith('workflow', {
            name: ['Name is too short'],
          });
        },
        { timeout: 1000 }
      );
    });

    it('should use errorPath when writing to Y.Doc', async () => {
      renderHook(() => useValidation(mockForm, 'jobs.job-123'));

      // Simulate form validation error on body field only
      mockForm.state.fieldMeta.body = {
        errors: ['Body is required'],
        isTouched: true,
      };
      mockForm.getFieldMeta.mockImplementation((fieldName: string) => {
        if (fieldName === 'body') {
          return { errors: ['Body is required'], isTouched: true };
        }
        return null;
      });

      // Trigger form subscription callback
      act(() => {
        subscribeCallbacks.forEach(cb => cb());
      });

      // Wait for debounced write
      await waitFor(
        () => {
          expect(mockSetClientErrors).toHaveBeenCalledWith('jobs.job-123', {
            body: ['Body is required'],
          });
        },
        { timeout: 1000 }
      );
    });

    it('should convert non-string errors to strings', async () => {
      renderHook(() => useValidation(mockForm));

      // Simulate form with non-string error on name field only
      mockForm.state.fieldMeta.name = {
        errors: [{ message: 'Complex error object' }, 123, null],
        isTouched: true,
      };
      mockForm.getFieldMeta.mockImplementation((fieldName: string) => {
        if (fieldName === 'name') {
          return {
            errors: [{ message: 'Complex error object' }, 123, null],
            isTouched: true,
          };
        }
        return null;
      });

      // Trigger form subscription
      act(() => {
        subscribeCallbacks.forEach(cb => cb());
      });

      // Wait for debounced write
      await waitFor(
        () => {
          expect(mockSetClientErrors).toHaveBeenCalledWith('workflow', {
            name: ['[object Object]', '123', 'null'],
          });
        },
        { timeout: 1000 }
      );
    });
  });

  describe('clearing errors', () => {
    it('should send empty array when field becomes valid', async () => {
      renderHook(() => useValidation(mockForm));

      // Simulate field becoming valid after being invalid
      mockForm.state.fieldMeta.name = {
        errors: [],
        isTouched: true,
      };
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

      // Should send empty array to clear the field
      await waitFor(
        () => {
          expect(mockSetClientErrors).toHaveBeenCalledWith('workflow', {
            name: [],
          });
        },
        { timeout: 1000 }
      );
    });

    it('should send empty array for multiple cleared fields', async () => {
      renderHook(() => useValidation(mockForm));

      // Simulate both fields becoming valid
      mockForm.state.fieldMeta.name = { errors: [], isTouched: true };
      mockForm.state.fieldMeta.body = { errors: [], isDirty: true };
      mockForm.getFieldMeta.mockImplementation((fieldName: string) => {
        if (fieldName === 'name') {
          return { errors: [], isTouched: true };
        }
        if (fieldName === 'body') {
          return { errors: [], isDirty: true };
        }
        return null;
      });

      // Trigger subscription
      act(() => {
        subscribeCallbacks.forEach(cb => cb());
      });

      // Should send empty arrays for both fields
      await waitFor(
        () => {
          expect(mockSetClientErrors).toHaveBeenCalledWith('workflow', {
            name: [],
            body: [],
          });
        },
        { timeout: 1000 }
      );
    });
  });

  describe('form subscription management', () => {
    it('should subscribe to form state changes', () => {
      renderHook(() => useValidation(mockForm));

      // Should have multiple subscriptions (one for each effect)
      expect(mockForm.store.subscribe).toHaveBeenCalled();
      expect(subscribeCallbacks.length).toBeGreaterThan(0);
    });

    it('should unsubscribe on unmount', () => {
      const unsubscribeFn = vi.fn();
      mockForm.store.subscribe.mockReturnValue(unsubscribeFn);

      const { unmount } = renderHook(() => useValidation(mockForm));

      // Verify subscription was created
      expect(mockForm.store.subscribe).toHaveBeenCalled();

      // Unmount and verify unsubscribe was called
      unmount();

      expect(unsubscribeFn).toHaveBeenCalled();
    });

    it('should handle multiple fields updating simultaneously', async () => {
      vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
        (selector: any) =>
          selector({
            workflow: {
              errors: {
                name: ['Name is required'],
                body: ['Body is required'],
              },
            },
            jobs: [],
            triggers: [],
            edges: [],
          })
      );

      renderHook(() => useValidation(mockForm));

      await waitFor(() => {
        // Both fields should be updated
        const nameCalls = mockForm.setFieldMeta.mock.calls.filter(
          (call: any) => call[0] === 'name'
        );
        const bodyCalls = mockForm.setFieldMeta.mock.calls.filter(
          (call: any) => call[0] === 'body'
        );

        expect(nameCalls.length).toBeGreaterThan(0);
        expect(bodyCalls.length).toBeGreaterThan(0);
      });
    });
  });

  describe('edge cases', () => {
    it('should handle form with no fields', () => {
      mockForm.state.values = {};

      expect(() => {
        renderHook(() => useValidation(mockForm));
      }).not.toThrow();
    });

    it('should handle errors for fields not in form values', async () => {
      vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
        (selector: any) =>
          selector({
            workflow: {
              errors: {
                nonexistent_field: ['Error on missing field'],
              },
            },
            jobs: [],
            triggers: [],
            edges: [],
          })
      );

      renderHook(() => useValidation(mockForm));

      // Should not crash
      await waitFor(() => {
        // Should not try to set error on nonexistent field
        const calls = mockForm.setFieldMeta.mock.calls.filter(
          (call: any) => call[0] === 'nonexistent_field'
        );
        expect(calls.length).toBe(0);
      });
    });

    it('should handle empty error arrays', async () => {
      vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
        (selector: any) =>
          selector({
            workflow: {
              errors: {
                name: [],
              },
            },
            jobs: [],
            triggers: [],
            edges: [],
          })
      );

      renderHook(() => useValidation(mockForm));

      await waitFor(() => {
        const calls = mockForm.setFieldMeta.mock.calls.filter(
          (call: any) => call[0] === 'name'
        );
        if (calls.length > 0) {
          const updaterFn = calls[0][1];
          const result = updaterFn({});
          // Empty array should result in undefined error
          expect(result.errorMap.collaborative).toBeUndefined();
        }
      });
    });

    it('should handle rapid state changes without errors', async () => {
      const { rerender } = renderHook(() => useValidation(mockForm));

      // Rapidly change state multiple times
      for (let i = 0; i < 5; i++) {
        vi.mocked(useWorkflowModule.useWorkflowState).mockImplementation(
          (selector: any) =>
            selector({
              workflow: { errors: { name: [`Error ${i}`] } },
              jobs: [],
              triggers: [],
              edges: [],
            })
        );
        rerender();
      }

      // Should not crash
      expect(mockForm.setFieldMeta).toHaveBeenCalled();
    });
  });
});
