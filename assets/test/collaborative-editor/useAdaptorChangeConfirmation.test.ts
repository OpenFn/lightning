/**
 * Tests for useAdaptorChangeConfirmation hook
 *
 * Tests the adaptor change confirmation logic that handles credential reset
 * warnings when users select a different adaptor.
 */

import { act, renderHook } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { useAdaptorChangeConfirmation } from '../../js/collaborative-editor/hooks/useAdaptorChangeConfirmation';
import type { Workflow } from '../../js/collaborative-editor/types/workflow';

describe('useAdaptorChangeConfirmation', () => {
  // Helper to create a test job
  const createJob = (overrides?: Partial<Workflow.Job>): Workflow.Job => ({
    id: 'job-1',
    name: 'Test Job',
    body: 'fn(state => state)',
    adaptor: '@openfn/language-http@1.0.0',
    project_credential_id: null,
    keychain_credential_id: null,
    ...overrides,
  });

  // Helper to create mock callbacks
  const createMocks = () => ({
    updateJob: vi.fn(),
    setIsAdaptorPickerOpen: vi.fn(),
    setIsConfigureModalOpen: vi.fn(),
    onAdaptorChangeStart: vi.fn(),
  });

  describe('confirmation display logic', () => {
    test('shows confirmation when job has project_credential_id and different adaptor selected', () => {
      const job = createJob({ project_credential_id: 'cred-1' });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-chatgpt@1.0.0');
      });

      expect(result.current.isAdaptorChangeConfirmationOpen).toBe(true);
      expect(mocks.setIsAdaptorPickerOpen).toHaveBeenCalledWith(false);
      expect(mocks.updateJob).not.toHaveBeenCalled(); // Should wait for confirmation
    });

    test('shows confirmation when job has keychain_credential_id and different adaptor selected', () => {
      const job = createJob({ keychain_credential_id: 'cred-1' });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-salesforce@2.0.0');
      });

      expect(result.current.isAdaptorChangeConfirmationOpen).toBe(true);
      expect(mocks.updateJob).not.toHaveBeenCalled();
    });

    test('skips confirmation when job has no credentials', () => {
      const job = createJob();
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-salesforce@1.0.0');
      });

      expect(result.current.isAdaptorChangeConfirmationOpen).toBe(false);
      expect(mocks.updateJob).toHaveBeenCalledWith('job-1', {
        adaptor: '@openfn/language-salesforce@latest',
      });
      expect(mocks.setIsAdaptorPickerOpen).toHaveBeenCalledWith(false);
      expect(mocks.setIsConfigureModalOpen).toHaveBeenCalledWith(true);
    });

    test('skips confirmation when selecting same adaptor package (different version)', () => {
      const job = createJob({
        adaptor: '@openfn/language-http@1.0.0',
        project_credential_id: 'cred-1',
      });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-http@2.0.0');
      });

      expect(result.current.isAdaptorChangeConfirmationOpen).toBe(false);
      expect(mocks.setIsAdaptorPickerOpen).toHaveBeenCalledWith(false);
      expect(mocks.setIsConfigureModalOpen).toHaveBeenCalledWith(true);
      expect(mocks.updateJob).not.toHaveBeenCalled(); // Same adaptor, no change needed
    });

    test('handles null job without crashing', () => {
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job: null,
          ...mocks,
        })
      );

      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-http@1.0.0');
      });

      expect(result.current.isAdaptorChangeConfirmationOpen).toBe(false);
      expect(mocks.updateJob).not.toHaveBeenCalled();
    });
  });

  describe('adaptor package parsing', () => {
    test('correctly parses @openfn/language-chatgpt@1.0.0', () => {
      const job = createJob({ project_credential_id: 'cred-1' });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-chatgpt@1.0.0');
      });

      // Confirm to see the final adaptor value
      act(() => {
        result.current.handleConfirmAdaptorChange();
      });

      expect(mocks.updateJob).toHaveBeenCalledWith(
        'job-1',
        expect.objectContaining({
          adaptor: '@openfn/language-chatgpt@latest',
        })
      );
    });

    test('correctly parses @openfn/language-chatgpt (no version)', () => {
      const job = createJob({ project_credential_id: 'cred-1' });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-chatgpt');
      });

      act(() => {
        result.current.handleConfirmAdaptorChange();
      });

      expect(mocks.updateJob).toHaveBeenCalledWith(
        'job-1',
        expect.objectContaining({
          adaptor: '@openfn/language-chatgpt@latest',
        })
      );
    });

    test('treats @openfn/language-http@1.0.0 and @openfn/language-http@2.0.0 as same package', () => {
      const job = createJob({
        adaptor: '@openfn/language-http@1.0.0',
        project_credential_id: 'cred-1',
      });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-http@2.0.0');
      });

      // Should skip confirmation
      expect(result.current.isAdaptorChangeConfirmationOpen).toBe(false);
      expect(mocks.setIsConfigureModalOpen).toHaveBeenCalledWith(true);
    });
  });

  describe('credential reset on confirm', () => {
    test('resets both credential fields when user confirms', () => {
      const job = createJob({
        project_credential_id: 'cred-1',
        keychain_credential_id: null,
      });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-salesforce@1.0.0');
      });

      act(() => {
        result.current.handleConfirmAdaptorChange();
      });

      expect(mocks.updateJob).toHaveBeenCalledWith('job-1', {
        adaptor: '@openfn/language-salesforce@latest',
        project_credential_id: null,
        keychain_credential_id: null,
      });
    });

    test('opens configure modal after confirmation', () => {
      const job = createJob({ project_credential_id: 'cred-1' });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-common@1.0.0');
      });

      act(() => {
        result.current.handleConfirmAdaptorChange();
      });

      expect(mocks.setIsConfigureModalOpen).toHaveBeenCalledWith(true);
      expect(result.current.isAdaptorChangeConfirmationOpen).toBe(false);
    });

    test('handles confirmation with null pending selection gracefully', () => {
      const job = createJob({ project_credential_id: 'cred-1' });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      // Call confirm without selecting an adaptor first
      act(() => {
        result.current.handleConfirmAdaptorChange();
      });

      expect(mocks.updateJob).not.toHaveBeenCalled();
    });

    test('handles confirmation with null job gracefully', () => {
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job: null,
          ...mocks,
        })
      );

      act(() => {
        result.current.handleConfirmAdaptorChange();
      });

      expect(mocks.updateJob).not.toHaveBeenCalled();
    });
  });

  describe('modal navigation', () => {
    test('opens confirmation modal -> configure modal on confirm', () => {
      const job = createJob({ project_credential_id: 'cred-1' });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      // Select different adaptor -> shows confirmation
      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-salesforce@1.0.0');
      });

      expect(result.current.isAdaptorChangeConfirmationOpen).toBe(true);
      expect(mocks.setIsAdaptorPickerOpen).toHaveBeenCalledWith(false);

      // Confirm -> opens configure modal
      act(() => {
        result.current.handleConfirmAdaptorChange();
      });

      expect(result.current.isAdaptorChangeConfirmationOpen).toBe(false);
      expect(mocks.setIsConfigureModalOpen).toHaveBeenCalledWith(true);
    });

    test('opens confirmation modal -> adaptor picker on cancel', () => {
      const job = createJob({ project_credential_id: 'cred-1' });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      // Select different adaptor -> shows confirmation
      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-salesforce@1.0.0');
      });

      expect(result.current.isAdaptorChangeConfirmationOpen).toBe(true);

      // Cancel -> returns to adaptor picker
      act(() => {
        result.current.handleCancelAdaptorChange();
      });

      expect(result.current.isAdaptorChangeConfirmationOpen).toBe(false);
      expect(mocks.setIsAdaptorPickerOpen).toHaveBeenCalledWith(true);
      expect(mocks.updateJob).not.toHaveBeenCalled();
    });

    test('opens confirmation modal -> adaptor picker on ESC (close)', () => {
      const job = createJob({ project_credential_id: 'cred-1' });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      // Select different adaptor -> shows confirmation
      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-salesforce@1.0.0');
      });

      // Close (ESC) -> returns to adaptor picker
      act(() => {
        result.current.handleCloseConfirmation();
      });

      expect(result.current.isAdaptorChangeConfirmationOpen).toBe(false);
      expect(mocks.setIsAdaptorPickerOpen).toHaveBeenCalledWith(true);
    });

    test('skips to configure modal directly when no confirmation needed', () => {
      const job = createJob(); // No credentials
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-salesforce@1.0.0');
      });

      expect(result.current.isAdaptorChangeConfirmationOpen).toBe(false);
      expect(mocks.setIsAdaptorPickerOpen).toHaveBeenCalledWith(false);
      expect(mocks.setIsConfigureModalOpen).toHaveBeenCalledWith(true);
    });
  });

  describe('optional callback', () => {
    test('calls onAdaptorChangeStart before Y.Doc update when provided', () => {
      const job = createJob({ project_credential_id: 'cred-1' });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-salesforce@1.0.0');
      });

      act(() => {
        result.current.handleConfirmAdaptorChange();
      });

      expect(mocks.onAdaptorChangeStart).toHaveBeenCalled();
      expect(mocks.updateJob).toHaveBeenCalled();
    });

    test('works without onAdaptorChangeStart callback', () => {
      const job = createJob({ project_credential_id: 'cred-1' });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          updateJob: mocks.updateJob,
          setIsAdaptorPickerOpen: mocks.setIsAdaptorPickerOpen,
          setIsConfigureModalOpen: mocks.setIsConfigureModalOpen,
          // No onAdaptorChangeStart provided
        })
      );

      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-salesforce@1.0.0');
      });

      act(() => {
        result.current.handleConfirmAdaptorChange();
      });

      expect(mocks.updateJob).toHaveBeenCalled();
    });

    test('calls onAdaptorChangeStart for immediate change (no credentials)', () => {
      const job = createJob(); // No credentials
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-salesforce@1.0.0');
      });

      expect(mocks.onAdaptorChangeStart).toHaveBeenCalled();
      expect(mocks.updateJob).toHaveBeenCalled();
    });
  });

  describe('AlertDialog dual-call handling', () => {
    test('handleCloseConfirmation does not navigate after confirm', () => {
      const job = createJob({ project_credential_id: 'cred-1' });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-salesforce@1.0.0');
      });

      // Simulate AlertDialog behavior: calls onConfirm then onClose
      act(() => {
        result.current.handleConfirmAdaptorChange();
      });

      mocks.setIsAdaptorPickerOpen.mockClear();

      // This should NOT navigate to adaptor picker
      act(() => {
        result.current.handleCloseConfirmation();
      });

      expect(mocks.setIsAdaptorPickerOpen).not.toHaveBeenCalled();
    });

    test('ref resets after microtask to allow future interactions', async () => {
      const job = createJob({ project_credential_id: 'cred-1' });
      const mocks = createMocks();

      const { result } = renderHook(() =>
        useAdaptorChangeConfirmation({
          job,
          ...mocks,
        })
      );

      // First interaction: confirm
      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-salesforce@1.0.0');
      });

      act(() => {
        result.current.handleConfirmAdaptorChange();
      });

      // Wait for microtask (setTimeout 0)
      await new Promise(resolve => setTimeout(resolve, 10));

      // Second interaction: should work normally
      act(() => {
        result.current.handleAdaptorSelect('@openfn/language-chatgpt@1.0.0');
      });

      mocks.setIsAdaptorPickerOpen.mockClear();

      act(() => {
        result.current.handleCloseConfirmation();
      });

      // Now it should navigate to adaptor picker again
      expect(mocks.setIsAdaptorPickerOpen).toHaveBeenCalledWith(true);
    });
  });
});
