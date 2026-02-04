/**
 * useAIPanelURLSync Tests
 *
 * Tests the URL parameter synchronization hook that manages bidirectional
 * sync between panel state and URL params with re-entrancy protection.
 */

import { renderHook } from '@testing-library/react';
import { describe, it, expect, beforeEach, vi } from 'vitest';

import type { AIModeResult } from '../../../js/collaborative-editor/hooks/useAIMode';
import { useAIPanelURLSync } from '../../../js/collaborative-editor/hooks/useAIPanelURLSync';
import type { AIAssistantStoreInstance } from '../../../js/collaborative-editor/stores/createAIAssistantStore';

describe('useAIPanelURLSync', () => {
  const mockUpdateSearchParams = vi.fn();

  // Mock AIStore
  const createMockAIStore = (
    sessionType: 'workflow_template' | 'job_code' | null = 'workflow_template'
  ): AIAssistantStoreInstance =>
    ({
      getSnapshot: vi.fn(() => ({ sessionType })),
      subscribe: vi.fn(),
      clearSession: vi.fn(),
      _clearSessionList: vi.fn(),
      _initializeContext: vi.fn(),
    }) as unknown as AIAssistantStoreInstance;

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
    // Fast-forward timers for setTimeout calls
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe('panel open/close sync', () => {
    it('sets chat=true when panel opens', () => {
      renderHook(() =>
        useAIPanelURLSync({
          isOpen: true,
          sessionId: null,
          aiMode: createMockAIMode('workflow_template'),
          aiStore: createMockAIStore(),
          updateSearchParams: mockUpdateSearchParams,
          params: {},
        })
      );

      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        chat: 'true',
      });
    });

    it('clears chat params when panel closes', () => {
      renderHook(() =>
        useAIPanelURLSync({
          isOpen: false,
          sessionId: null,
          aiMode: createMockAIMode('workflow_template'),
          aiStore: createMockAIStore(),
          updateSearchParams: mockUpdateSearchParams,
          params: {},
        })
      );

      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        chat: null,
        'w-chat': null,
        'j-chat': null,
      });
    });

    it('prevents re-entrant updates using setTimeout', () => {
      const { rerender } = renderHook(
        ({ isOpen }) =>
          useAIPanelURLSync({
            isOpen,
            sessionId: null,
            aiMode: createMockAIMode('workflow_template'),
            aiStore: createMockAIStore(),
            updateSearchParams: mockUpdateSearchParams,
            params: {},
          }),
        { initialProps: { isOpen: true } }
      );

      expect(mockUpdateSearchParams).toHaveBeenCalledTimes(1);

      // Rerender immediately (simulating URL param change triggering rerender)
      rerender({ isOpen: true });

      // Should not call again due to isSyncingRef guard
      expect(mockUpdateSearchParams).toHaveBeenCalledTimes(1);

      // Fast-forward past setTimeout
      vi.advanceTimersByTime(10);

      // Now rerender should work
      rerender({ isOpen: false });
      expect(mockUpdateSearchParams).toHaveBeenCalledTimes(2);
    });
  });

  describe('session ID sync to URL', () => {
    it('syncs workflow session ID to w-chat param', () => {
      vi.clearAllMocks();

      renderHook(() =>
        useAIPanelURLSync({
          isOpen: true,
          sessionId: 'session-123',
          aiMode: createMockAIMode('workflow_template'),
          aiStore: createMockAIStore('workflow_template'),
          updateSearchParams: mockUpdateSearchParams,
          params: {},
        })
      );

      // Skip the initial panel open sync call
      vi.advanceTimersByTime(10);
      vi.clearAllMocks();

      // Trigger session ID sync effect
      renderHook(() =>
        useAIPanelURLSync({
          isOpen: true,
          sessionId: 'session-123',
          aiMode: createMockAIMode('workflow_template'),
          aiStore: createMockAIStore('workflow_template'),
          updateSearchParams: mockUpdateSearchParams,
          params: {},
        })
      );

      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        'w-chat': 'session-123',
        'j-chat': null,
      });
    });

    it('syncs job session ID to j-chat param', () => {
      vi.clearAllMocks();

      renderHook(() =>
        useAIPanelURLSync({
          isOpen: true,
          sessionId: 'session-456',
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          aiStore: createMockAIStore('job_code'),
          updateSearchParams: mockUpdateSearchParams,
          params: {},
        })
      );

      // Skip the initial panel open sync call
      vi.advanceTimersByTime(10);
      vi.clearAllMocks();

      // Trigger session ID sync effect
      renderHook(() =>
        useAIPanelURLSync({
          isOpen: true,
          sessionId: 'session-456',
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          aiStore: createMockAIStore('job_code'),
          updateSearchParams: mockUpdateSearchParams,
          params: {},
        })
      );

      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        'j-chat': 'session-456',
        'w-chat': null,
      });
    });

    it('does not sync when panel is closed', () => {
      vi.clearAllMocks();

      renderHook(() =>
        useAIPanelURLSync({
          isOpen: false,
          sessionId: 'session-123',
          aiMode: createMockAIMode('workflow_template'),
          aiStore: createMockAIStore('workflow_template'),
          updateSearchParams: mockUpdateSearchParams,
          params: {},
        })
      );

      // Should only call for panel close, not session ID sync
      expect(mockUpdateSearchParams).toHaveBeenCalledTimes(1);
      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        chat: null,
        'w-chat': null,
        'j-chat': null,
      });
    });

    it('does not sync when sessionId is null', () => {
      vi.clearAllMocks();

      const { rerender } = renderHook(
        ({ sessionId }) =>
          useAIPanelURLSync({
            isOpen: true,
            sessionId,
            aiMode: createMockAIMode('workflow_template'),
            aiStore: createMockAIStore('workflow_template'),
            updateSearchParams: mockUpdateSearchParams,
            params: {},
          }),
        { initialProps: { sessionId: null } }
      );

      // Clear initial panel open sync
      vi.advanceTimersByTime(10);
      vi.clearAllMocks();

      // Rerender with null sessionId
      rerender({ sessionId: null });

      // Should not sync session ID to URL
      expect(mockUpdateSearchParams).not.toHaveBeenCalled();
    });

    it('does not sync when aiMode is null', () => {
      vi.clearAllMocks();

      renderHook(() =>
        useAIPanelURLSync({
          isOpen: true,
          sessionId: 'session-123',
          aiMode: null,
          aiStore: createMockAIStore('workflow_template'),
          updateSearchParams: mockUpdateSearchParams,
          params: {},
        })
      );

      // Should only call for panel open sync
      vi.advanceTimersByTime(10);
      expect(mockUpdateSearchParams).toHaveBeenCalledTimes(1);
      expect(mockUpdateSearchParams).toHaveBeenCalledWith({ chat: 'true' });
    });

    it('only syncs when session type matches mode', () => {
      vi.clearAllMocks();

      const { rerender } = renderHook(
        ({ sessionId }) =>
          useAIPanelURLSync({
            isOpen: true,
            sessionId,
            aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
            aiStore: createMockAIStore('workflow_template'), // Mismatch
            updateSearchParams: mockUpdateSearchParams,
            params: {},
          }),
        { initialProps: { sessionId: null } }
      );

      // Clear initial panel open sync
      vi.advanceTimersByTime(10);
      vi.clearAllMocks();

      // Add session ID - should not sync due to type mismatch
      rerender({ sessionId: 'session-123' });

      // Should not sync session ID due to type mismatch
      expect(mockUpdateSearchParams).not.toHaveBeenCalled();
    });
  });

  describe('sessionIdFromURL', () => {
    it('returns w-chat param in workflow mode', () => {
      const { result } = renderHook(() =>
        useAIPanelURLSync({
          isOpen: true,
          sessionId: null,
          aiMode: createMockAIMode('workflow_template'),
          aiStore: createMockAIStore(),
          updateSearchParams: mockUpdateSearchParams,
          params: { 'w-chat': 'session-from-url' },
        })
      );

      expect(result.current.sessionIdFromURL).toBe('session-from-url');
    });

    it('returns j-chat param in job mode', () => {
      const { result } = renderHook(() =>
        useAIPanelURLSync({
          isOpen: true,
          sessionId: null,
          aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
          aiStore: createMockAIStore('job_code'),
          updateSearchParams: mockUpdateSearchParams,
          params: { 'j-chat': 'job-session-from-url' },
        })
      );

      expect(result.current.sessionIdFromURL).toBe('job-session-from-url');
    });

    it('returns null when aiMode is null', () => {
      const { result } = renderHook(() =>
        useAIPanelURLSync({
          isOpen: true,
          sessionId: null,
          aiMode: null,
          aiStore: createMockAIStore(),
          updateSearchParams: mockUpdateSearchParams,
          params: { 'w-chat': 'session-123' },
        })
      );

      expect(result.current.sessionIdFromURL).toBeNull();
    });

    it('normalizes undefined to null', () => {
      const { result } = renderHook(() =>
        useAIPanelURLSync({
          isOpen: true,
          sessionId: null,
          aiMode: createMockAIMode('workflow_template'),
          aiStore: createMockAIStore(),
          updateSearchParams: mockUpdateSearchParams,
          params: {}, // No w-chat param = undefined
        })
      );

      expect(result.current.sessionIdFromURL).toBeNull();
    });

    it('updates reactively when params change', () => {
      const { result, rerender } = renderHook(
        ({ params }) =>
          useAIPanelURLSync({
            isOpen: true,
            sessionId: null,
            aiMode: createMockAIMode('workflow_template'),
            aiStore: createMockAIStore(),
            updateSearchParams: mockUpdateSearchParams,
            params,
          }),
        { initialProps: { params: {} } }
      );

      expect(result.current.sessionIdFromURL).toBeNull();

      // Add param to URL
      rerender({ params: { 'w-chat': 'new-session' } });

      expect(result.current.sessionIdFromURL).toBe('new-session');
    });
  });

  describe('mode switching', () => {
    it('clears job param when switching to workflow mode', () => {
      vi.clearAllMocks();

      const { rerender } = renderHook(
        ({ aiMode, aiStore }) =>
          useAIPanelURLSync({
            isOpen: true,
            sessionId: 'session-123',
            aiMode,
            aiStore,
            updateSearchParams: mockUpdateSearchParams,
            params: { 'j-chat': 'job-session' },
          }),
        {
          initialProps: {
            aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
            aiStore: createMockAIStore('job_code'),
          },
        }
      );

      // Clear initial calls
      vi.advanceTimersByTime(10);
      vi.clearAllMocks();

      // Switch to workflow mode
      rerender({
        aiMode: createMockAIMode('workflow_template'),
        aiStore: createMockAIStore('workflow_template'),
      });

      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        'w-chat': 'session-123',
        'j-chat': null, // Clears job param
      });
    });

    it('clears workflow param when switching to job mode', () => {
      vi.clearAllMocks();

      const { rerender } = renderHook(
        ({ aiMode, aiStore }) =>
          useAIPanelURLSync({
            isOpen: true,
            sessionId: 'session-456',
            aiMode,
            aiStore,
            updateSearchParams: mockUpdateSearchParams,
            params: { 'w-chat': 'workflow-session' },
          }),
        {
          initialProps: {
            aiMode: createMockAIMode('workflow_template'),
            aiStore: createMockAIStore('workflow_template'),
          },
        }
      );

      // Clear initial calls
      vi.advanceTimersByTime(10);
      vi.clearAllMocks();

      // Switch to job mode
      rerender({
        aiMode: createMockAIMode('job_code', { job_id: 'job-1' }),
        aiStore: createMockAIStore('job_code'),
      });

      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        'j-chat': 'session-456',
        'w-chat': null, // Clears workflow param
      });
    });
  });

  describe('edge cases', () => {
    it('handles empty params object', () => {
      const { result } = renderHook(() =>
        useAIPanelURLSync({
          isOpen: true,
          sessionId: null,
          aiMode: createMockAIMode('workflow_template'),
          aiStore: createMockAIStore(),
          updateSearchParams: mockUpdateSearchParams,
          params: {},
        })
      );

      expect(result.current.sessionIdFromURL).toBeNull();
    });

    it('handles params with other unrelated keys', () => {
      const { result } = renderHook(() =>
        useAIPanelURLSync({
          isOpen: true,
          sessionId: null,
          aiMode: createMockAIMode('workflow_template'),
          aiStore: createMockAIStore(),
          updateSearchParams: mockUpdateSearchParams,
          params: {
            'w-chat': 'session-123',
            page: '2',
            filter: 'active',
          },
        })
      );

      expect(result.current.sessionIdFromURL).toBe('session-123');
    });

    it('skips update when param already matches sessionId', () => {
      vi.clearAllMocks();

      renderHook(() =>
        useAIPanelURLSync({
          isOpen: true,
          sessionId: 'session-123',
          aiMode: createMockAIMode('workflow_template'),
          aiStore: createMockAIStore('workflow_template'),
          updateSearchParams: mockUpdateSearchParams,
          params: { 'w-chat': 'session-123' }, // Already matches
        })
      );

      // Should only sync panel open, not session ID (already synced)
      vi.advanceTimersByTime(10);
      expect(mockUpdateSearchParams).toHaveBeenCalledTimes(1);
      expect(mockUpdateSearchParams).toHaveBeenCalledWith({ chat: 'true' });
    });

    it('handles rapid session ID changes', () => {
      vi.clearAllMocks();

      const { rerender } = renderHook(
        ({ sessionId }) =>
          useAIPanelURLSync({
            isOpen: true,
            sessionId,
            aiMode: createMockAIMode('workflow_template'),
            aiStore: createMockAIStore('workflow_template'),
            updateSearchParams: mockUpdateSearchParams,
            params: {},
          }),
        { initialProps: { sessionId: 'session-1' } }
      );

      vi.advanceTimersByTime(10);
      vi.clearAllMocks();

      // Rapidly change session IDs
      rerender({ sessionId: 'session-2' });
      rerender({ sessionId: 'session-3' });
      rerender({ sessionId: 'session-4' });

      // Should handle all changes
      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        'w-chat': 'session-4',
        'j-chat': null,
      });
    });
  });
});
