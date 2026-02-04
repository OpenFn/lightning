/**
 * useAIPanelDiffManager Tests
 *
 * Tests the diff preview lifecycle management hook that handles clearing
 * Monaco diffs when context changes (panel close, version change, job change).
 */

import { renderHook } from '@testing-library/react';
import { describe, it, expect, beforeEach, vi } from 'vitest';

import type { MonacoHandle } from '../../../js/collaborative-editor/components/CollaborativeMonaco';
import type { AIModeResult } from '../../../js/collaborative-editor/hooks/useAIMode';
import { useAIPanelDiffManager } from '../../../js/collaborative-editor/hooks/useAIPanelDiffManager';
import type { AIAssistantStoreInstance } from '../../../js/collaborative-editor/stores/createAIAssistantStore';

describe('useAIPanelDiffManager', () => {
  // Mock functions
  const mockClearDiff = vi.fn();
  const mockShowDiff = vi.fn();
  const mockCloseAIAssistantPanel = vi.fn();
  const mockUpdateSearchParams = vi.fn();
  const mockSetPreviewingMessageId = vi.fn();

  // Mock AIStore
  const mockAIStore = {
    clearSession: vi.fn(),
    _clearSessionList: vi.fn(),
    _initializeContext: vi.fn(),
    getSnapshot: vi.fn(),
    subscribe: vi.fn(),
  } as unknown as AIAssistantStoreInstance;

  // Mock Monaco ref
  const createMockMonacoRef = () => ({
    current: {
      clearDiff: mockClearDiff,
      showDiff: mockShowDiff,
    } as MonacoHandle,
  });

  // Mock AI mode
  const createMockAIMode = (
    mode: 'workflow_template' | 'job_code',
    context: Record<string, unknown> = {}
  ): AIModeResult => ({
    mode,
    context,
    storageKey: `ai-${mode}`,
  });

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('handleClosePanel', () => {
    it('clears diff and calls onPanelClose when previewing', () => {
      const monacoRef = createMockMonacoRef();

      const { result } = renderHook(() =>
        useAIPanelDiffManager({
          isOpen: true,
          previewingMessageId: 'msg-1',
          setPreviewingMessageId: mockSetPreviewingMessageId,
          monacoRef,
          currentVersion: undefined,
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          closeAIAssistantPanel: mockCloseAIAssistantPanel,
          aiStore: mockAIStore,
          updateSearchParams: mockUpdateSearchParams,
        })
      );

      result.current.handleClosePanel();

      expect(mockClearDiff).toHaveBeenCalledOnce();
      expect(mockSetPreviewingMessageId).toHaveBeenCalledWith(null);
      expect(mockCloseAIAssistantPanel).toHaveBeenCalledOnce();
    });

    it('only calls onPanelClose when not previewing', () => {
      const monacoRef = createMockMonacoRef();

      const { result } = renderHook(() =>
        useAIPanelDiffManager({
          isOpen: true,
          previewingMessageId: null,
          setPreviewingMessageId: mockSetPreviewingMessageId,
          monacoRef,
          currentVersion: undefined,
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          closeAIAssistantPanel: mockCloseAIAssistantPanel,
          aiStore: mockAIStore,
          updateSearchParams: mockUpdateSearchParams,
        })
      );

      result.current.handleClosePanel();

      expect(mockClearDiff).not.toHaveBeenCalled();
      expect(mockSetPreviewingMessageId).not.toHaveBeenCalled();
      expect(mockCloseAIAssistantPanel).toHaveBeenCalledOnce();
    });

    it('handles missing Monaco ref gracefully', () => {
      const { result } = renderHook(() =>
        useAIPanelDiffManager({
          isOpen: true,
          previewingMessageId: 'msg-1',
          setPreviewingMessageId: mockSetPreviewingMessageId,
          monacoRef: null,
          currentVersion: undefined,
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          closeAIAssistantPanel: mockCloseAIAssistantPanel,
          aiStore: mockAIStore,
          updateSearchParams: mockUpdateSearchParams,
        })
      );

      result.current.handleClosePanel();

      // Should not throw, just call close
      expect(mockCloseAIAssistantPanel).toHaveBeenCalledOnce();
      expect(mockClearDiff).not.toHaveBeenCalled();
    });
  });

  describe('handleShowSessions', () => {
    it('clears diff and shows session list', () => {
      const monacoRef = createMockMonacoRef();
      const aiMode = createMockAIMode('workflow_template', {
        project_id: 'proj-1',
      });

      const { result } = renderHook(() =>
        useAIPanelDiffManager({
          isOpen: true,
          previewingMessageId: 'msg-1',
          setPreviewingMessageId: mockSetPreviewingMessageId,
          monacoRef,
          currentVersion: undefined,
          aiMode,
          closeAIAssistantPanel: mockCloseAIAssistantPanel,
          aiStore: mockAIStore,
          updateSearchParams: mockUpdateSearchParams,
        })
      );

      result.current.handleShowSessions();

      // Clears diff
      expect(mockClearDiff).toHaveBeenCalledOnce();
      expect(mockSetPreviewingMessageId).toHaveBeenCalledWith(null);

      // Clears AI session and reinitializes
      expect(mockAIStore.clearSession).toHaveBeenCalledOnce();
      expect(mockAIStore._clearSessionList).toHaveBeenCalledOnce();
      expect(mockAIStore._initializeContext).toHaveBeenCalledWith(
        'workflow_template',
        { project_id: 'proj-1' }
      );

      // Clears URL params
      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        'w-chat': null,
        'j-chat': null,
      });
    });

    it('handles null aiMode gracefully', () => {
      const monacoRef = createMockMonacoRef();

      const { result } = renderHook(() =>
        useAIPanelDiffManager({
          isOpen: true,
          previewingMessageId: 'msg-1',
          setPreviewingMessageId: mockSetPreviewingMessageId,
          monacoRef,
          currentVersion: undefined,
          aiMode: null,
          closeAIAssistantPanel: mockCloseAIAssistantPanel,
          aiStore: mockAIStore,
          updateSearchParams: mockUpdateSearchParams,
        })
      );

      result.current.handleShowSessions();

      // Should not call _initializeContext with null mode
      expect(mockAIStore._initializeContext).not.toHaveBeenCalled();
      // But still clears session and URL
      expect(mockAIStore.clearSession).toHaveBeenCalledOnce();
      expect(mockUpdateSearchParams).toHaveBeenCalled();
    });
  });

  describe('version change effect', () => {
    it('clears diff when switching from latest to pinned version', () => {
      const monacoRef = createMockMonacoRef();

      const { rerender } = renderHook(
        ({ currentVersion }) =>
          useAIPanelDiffManager({
            isOpen: true,
            previewingMessageId: 'msg-1',
            setPreviewingMessageId: mockSetPreviewingMessageId,
            monacoRef,
            currentVersion,
            aiMode: createMockAIMode('workflow_template', {
              workflow_id: 'wf-1',
            }),
            closeAIAssistantPanel: mockCloseAIAssistantPanel,
            aiStore: mockAIStore,
            updateSearchParams: mockUpdateSearchParams,
          }),
        { initialProps: { currentVersion: undefined } }
      );

      // Initial render - no effect
      expect(mockClearDiff).not.toHaveBeenCalled();

      // Switch to pinned version
      rerender({ currentVersion: 'v1.0' });

      // Should clear diff and close panel
      expect(mockClearDiff).toHaveBeenCalledOnce();
      expect(mockSetPreviewingMessageId).toHaveBeenCalledWith(null);
      expect(mockCloseAIAssistantPanel).toHaveBeenCalledOnce();
      expect(mockAIStore.clearSession).toHaveBeenCalledOnce();
      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        'w-chat': null,
        'j-chat': null,
      });
    });

    it('clears diff and closes panel when switching between pinned versions', () => {
      const monacoRef = createMockMonacoRef();

      const { rerender } = renderHook(
        ({ currentVersion }) =>
          useAIPanelDiffManager({
            isOpen: true,
            previewingMessageId: 'msg-1',
            setPreviewingMessageId: mockSetPreviewingMessageId,
            monacoRef,
            currentVersion,
            aiMode: createMockAIMode('workflow_template', {
              workflow_id: 'wf-1',
            }),
            closeAIAssistantPanel: mockCloseAIAssistantPanel,
            aiStore: mockAIStore,
            updateSearchParams: mockUpdateSearchParams,
          }),
        { initialProps: { currentVersion: 'v1.0' } }
      );

      vi.clearAllMocks();

      // Switch to different pinned version
      rerender({ currentVersion: 'v2.0' });

      // Should clear diff AND close panel (switching TO pinned version)
      expect(mockClearDiff).toHaveBeenCalledOnce();
      expect(mockSetPreviewingMessageId).toHaveBeenCalledWith(null);
      expect(mockCloseAIAssistantPanel).toHaveBeenCalledOnce();
    });

    it('does not clear diff on initial mount', () => {
      const monacoRef = createMockMonacoRef();

      renderHook(() =>
        useAIPanelDiffManager({
          isOpen: true,
          previewingMessageId: 'msg-1',
          setPreviewingMessageId: mockSetPreviewingMessageId,
          monacoRef,
          currentVersion: 'v1.0',
          aiMode: createMockAIMode('workflow_template', {
            workflow_id: 'wf-1',
          }),
          closeAIAssistantPanel: mockCloseAIAssistantPanel,
          aiStore: mockAIStore,
          updateSearchParams: mockUpdateSearchParams,
        })
      );

      // First render should not trigger effect
      expect(mockClearDiff).not.toHaveBeenCalled();
      expect(mockCloseAIAssistantPanel).not.toHaveBeenCalled();
    });

    it('does not close panel when switching from pinned to latest (not previewing)', () => {
      const monacoRef = createMockMonacoRef();

      const { rerender } = renderHook(
        ({ currentVersion }) =>
          useAIPanelDiffManager({
            isOpen: true,
            previewingMessageId: null, // Not previewing
            setPreviewingMessageId: mockSetPreviewingMessageId,
            monacoRef,
            currentVersion,
            aiMode: createMockAIMode('workflow_template', {
              workflow_id: 'wf-1',
            }),
            closeAIAssistantPanel: mockCloseAIAssistantPanel,
            aiStore: mockAIStore,
            updateSearchParams: mockUpdateSearchParams,
          }),
        { initialProps: { currentVersion: 'v1.0' } }
      );

      vi.clearAllMocks();

      // Switch to latest (undefined)
      rerender({ currentVersion: undefined });

      // Should not close panel when going back to latest
      expect(mockCloseAIAssistantPanel).not.toHaveBeenCalled();
      expect(mockClearDiff).not.toHaveBeenCalled(); // No preview active
    });
  });

  describe('job change effect', () => {
    it('clears diff when switching between jobs in job_code mode', () => {
      const monacoRef = createMockMonacoRef();

      const { rerender } = renderHook(
        ({ aiMode }) =>
          useAIPanelDiffManager({
            isOpen: true,
            previewingMessageId: 'msg-1',
            setPreviewingMessageId: mockSetPreviewingMessageId,
            monacoRef,
            currentVersion: undefined,
            aiMode,
            closeAIAssistantPanel: mockCloseAIAssistantPanel,
            aiStore: mockAIStore,
            updateSearchParams: mockUpdateSearchParams,
          }),
        {
          initialProps: {
            aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          },
        }
      );

      // Initial render - sets previousJobIdRef, no clear
      expect(mockClearDiff).not.toHaveBeenCalled();

      vi.clearAllMocks();

      // Switch to different job
      rerender({ aiMode: createMockAIMode('job_code', { job_id: 'job-2' }) });

      // Should clear diff when job changes
      expect(mockClearDiff).toHaveBeenCalledOnce();
      expect(mockSetPreviewingMessageId).toHaveBeenCalledWith(null);
    });

    it('does not clear diff on initial mount in job_code mode', () => {
      const monacoRef = createMockMonacoRef();

      renderHook(() =>
        useAIPanelDiffManager({
          isOpen: true,
          previewingMessageId: 'msg-1',
          setPreviewingMessageId: mockSetPreviewingMessageId,
          monacoRef,
          currentVersion: undefined,
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          closeAIAssistantPanel: mockCloseAIAssistantPanel,
          aiStore: mockAIStore,
          updateSearchParams: mockUpdateSearchParams,
        })
      );

      // First render should not clear diff
      expect(mockClearDiff).not.toHaveBeenCalled();
    });

    it('handles missing job_id gracefully', () => {
      const monacoRef = createMockMonacoRef();

      const { rerender } = renderHook(
        ({ aiMode }) =>
          useAIPanelDiffManager({
            isOpen: true,
            previewingMessageId: 'msg-1',
            setPreviewingMessageId: mockSetPreviewingMessageId,
            monacoRef,
            currentVersion: undefined,
            aiMode,
            closeAIAssistantPanel: mockCloseAIAssistantPanel,
            aiStore: mockAIStore,
            updateSearchParams: mockUpdateSearchParams,
          }),
        {
          initialProps: {
            aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          },
        }
      );

      vi.clearAllMocks();

      // Switch to mode with undefined job_id
      rerender({ aiMode: createMockAIMode('job_code', {}) });

      // Should handle gracefully by returning early (no diff clear)
      // No errors thrown, tracking resets to null
      expect(mockClearDiff).not.toHaveBeenCalled();
    });

    it('only runs in job_code mode', () => {
      const monacoRef = createMockMonacoRef();

      const { rerender } = renderHook(
        ({ aiMode }) =>
          useAIPanelDiffManager({
            isOpen: true,
            previewingMessageId: 'msg-1',
            setPreviewingMessageId: mockSetPreviewingMessageId,
            monacoRef,
            currentVersion: undefined,
            aiMode,
            closeAIAssistantPanel: mockCloseAIAssistantPanel,
            aiStore: mockAIStore,
            updateSearchParams: mockUpdateSearchParams,
          }),
        {
          initialProps: {
            aiMode: createMockAIMode('workflow_template', {
              workflow_id: 'wf-1',
            }),
          },
        }
      );

      vi.clearAllMocks();

      // Switch to different workflow (not job mode)
      rerender({
        aiMode: createMockAIMode('workflow_template', { workflow_id: 'wf-2' }),
      });

      // Should not clear diff (not in job_code mode)
      expect(mockClearDiff).not.toHaveBeenCalled();
    });

    it('resets tracking when switching from job_code to workflow mode', () => {
      const monacoRef = createMockMonacoRef();

      const { rerender } = renderHook(
        ({ aiMode }) =>
          useAIPanelDiffManager({
            isOpen: true,
            previewingMessageId: 'msg-1',
            setPreviewingMessageId: mockSetPreviewingMessageId,
            monacoRef,
            currentVersion: undefined,
            aiMode,
            closeAIAssistantPanel: mockCloseAIAssistantPanel,
            aiStore: mockAIStore,
            updateSearchParams: mockUpdateSearchParams,
          }),
        {
          initialProps: {
            aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          },
        }
      );

      vi.clearAllMocks();

      // Switch to workflow mode
      rerender({
        aiMode: createMockAIMode('workflow_template', { workflow_id: 'wf-1' }),
      });

      // Should reset tracking (previousJobIdRef = null)
      expect(mockClearDiff).not.toHaveBeenCalled(); // No clear when leaving job mode

      vi.clearAllMocks();

      // Switch back to job mode
      rerender({ aiMode: createMockAIMode('job_code', { job_id: 'job-2' }) });

      // Should not clear on first render after returning to job mode
      expect(mockClearDiff).not.toHaveBeenCalled();
    });
  });

  describe('edge cases', () => {
    it('handles panel closed state', () => {
      const monacoRef = createMockMonacoRef();

      renderHook(() =>
        useAIPanelDiffManager({
          isOpen: false,
          previewingMessageId: 'msg-1',
          setPreviewingMessageId: mockSetPreviewingMessageId,
          monacoRef,
          currentVersion: undefined,
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          closeAIAssistantPanel: mockCloseAIAssistantPanel,
          aiStore: mockAIStore,
          updateSearchParams: mockUpdateSearchParams,
        })
      );

      // Should not cause issues when panel is closed
      expect(() => mockClearDiff).not.toThrow();
    });

    it('handles rapid mode switches', () => {
      const monacoRef = createMockMonacoRef();

      const { rerender } = renderHook(
        ({ aiMode }) =>
          useAIPanelDiffManager({
            isOpen: true,
            previewingMessageId: 'msg-1',
            setPreviewingMessageId: mockSetPreviewingMessageId,
            monacoRef,
            currentVersion: undefined,
            aiMode,
            closeAIAssistantPanel: mockCloseAIAssistantPanel,
            aiStore: mockAIStore,
            updateSearchParams: mockUpdateSearchParams,
          }),
        {
          initialProps: {
            aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          },
        }
      );

      vi.clearAllMocks();

      // Rapidly switch between jobs
      rerender({ aiMode: createMockAIMode('job_code', { job_id: 'job-2' }) });
      rerender({ aiMode: createMockAIMode('job_code', { job_id: 'job-3' }) });
      rerender({ aiMode: createMockAIMode('job_code', { job_id: 'job-4' }) });

      // Should handle all switches correctly
      expect(mockClearDiff).toHaveBeenCalledTimes(3);
    });
  });
});
