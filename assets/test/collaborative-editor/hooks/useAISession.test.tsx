/**
 * useAISession - Tests for AI Session hook
 *
 * Tests the hook that manages AI session channel lifecycle with registry pattern.
 * Focuses on mode switching, job switching, and context initialization.
 */

import { renderHook } from '@testing-library/react';
import { type ReactNode } from 'react';
import {
  describe,
  it,
  expect,
  beforeEach,
  vi,
  type MockInstance,
} from 'vitest';

import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { useAISession } from '../../../js/collaborative-editor/hooks/useAISession';
import { createAIAssistantStore } from '../../../js/collaborative-editor/stores/createAIAssistantStore';
import type { JobCodeContext } from '../../../js/collaborative-editor/types/ai-assistant';

// Mock the registry hook
const mockUnsubscribe = vi.fn();
const mockUnsubscribeImmediate = vi.fn();
const mockSubscribe = vi.fn();
const mockRegistry = {
  subscribe: mockSubscribe,
  unsubscribe: mockUnsubscribe,
  unsubscribeImmediate: mockUnsubscribeImmediate,
};

vi.mock('../../../js/collaborative-editor/hooks/useAIChannelRegistry', () => ({
  useAIChannelRegistry: () => ({ registry: mockRegistry }),
  buildChannelTopic: (mode: string, sessionId: string | null) =>
    sessionId ? `ai:${mode}:${sessionId}` : `ai:${mode}:new`,
}));

describe('useAISession', () => {
  let mockStore: ReturnType<typeof createAIAssistantStore>;
  let wrapper: ({ children }: { children: ReactNode }) => JSX.Element;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let onSessionIdChange: MockInstance<any[], any>;

  beforeEach(() => {
    vi.clearAllMocks();

    // Create fresh store for each test
    mockStore = createAIAssistantStore();

    // Mock internal methods we need to spy on
    vi.spyOn(mockStore, '_clearSession');
    vi.spyOn(mockStore, '_clearSessionList');
    vi.spyOn(mockStore, '_setConnectionState');
    vi.spyOn(mockStore, '_initializeContext');

    onSessionIdChange = vi.fn();

    // Wrapper component that provides store context
    wrapper = ({ children }: { children: ReactNode }) => (
      <StoreContext.Provider
        value={
          {
            aiAssistantStore: mockStore,
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
          } as any
        }
      >
        {children}
      </StoreContext.Provider>
    );
  });

  describe('Job Switching within job_code mode', () => {
    it('should clear session and list when job changes', () => {
      const initialContext: JobCodeContext = {
        job_id: 'job-1',
        attach_code: false,
        attach_logs: false,
      };

      const { rerender } = renderHook(
        (props: { jobId: string }) =>
          useAISession({
            isOpen: true,
            aiMode: {
              mode: 'job_code',
              context: { ...initialContext, job_id: props.jobId },
            },
            sessionIdFromURL: null,
            onSessionIdChange,
          }),
        {
          wrapper,
          initialProps: { jobId: 'job-1' },
        }
      );

      // Clear mocks after initial render
      vi.clearAllMocks();

      // Switch to a different job
      rerender({ jobId: 'job-2' });

      // Should clear session and session list
      expect(mockStore._clearSession).toHaveBeenCalled();
      expect(mockStore._clearSessionList).toHaveBeenCalled();
      expect(mockStore._setConnectionState).toHaveBeenCalledWith(
        'disconnected'
      );
      expect(onSessionIdChange).toHaveBeenCalledWith(null);
    });

    it('should unsubscribe immediately when job changes', () => {
      // Set up initial subscription by first render with a session
      const initialContext: JobCodeContext = {
        job_id: 'job-1',
        attach_code: false,
        attach_logs: false,
      };

      const { rerender } = renderHook(
        (props: { jobId: string; sessionId: string | null }) =>
          useAISession({
            isOpen: true,
            aiMode: {
              mode: 'job_code',
              context: { ...initialContext, job_id: props.jobId },
            },
            sessionIdFromURL: props.sessionId,
            onSessionIdChange,
          }),
        {
          wrapper,
          initialProps: { jobId: 'job-1', sessionId: 'session-123' },
        }
      );

      // Clear mocks after initial render
      vi.clearAllMocks();

      // Switch to a different job
      rerender({ jobId: 'job-2', sessionId: 'session-123' });

      // Should unsubscribe immediately (not with delay)
      expect(mockUnsubscribeImmediate).toHaveBeenCalled();
    });

    it('should re-initialize context when job changes', () => {
      const initialContext: JobCodeContext = {
        job_id: 'job-1',
        attach_code: false,
        attach_logs: false,
      };

      const { rerender } = renderHook(
        (props: { jobId: string }) =>
          useAISession({
            isOpen: true,
            aiMode: {
              mode: 'job_code',
              context: { ...initialContext, job_id: props.jobId },
            },
            sessionIdFromURL: null,
            onSessionIdChange,
          }),
        {
          wrapper,
          initialProps: { jobId: 'job-1' },
        }
      );

      // Clear mocks after initial render
      vi.clearAllMocks();

      // Switch to a different job
      rerender({ jobId: 'job-2' });

      // Should re-initialize context with new job
      expect(mockStore._initializeContext).toHaveBeenCalledWith('job_code', {
        ...initialContext,
        job_id: 'job-2',
      });
    });

    it('should detect context mismatch when stored job_id differs', () => {
      // Start with job-1 in context
      mockStore._initializeContext('job_code', {
        job_id: 'job-old',
        attach_code: false,
        attach_logs: false,
      });

      renderHook(
        (props: { jobId: string }) =>
          useAISession({
            isOpen: true,
            aiMode: {
              mode: 'job_code',
              context: {
                job_id: props.jobId,
                attach_code: false,
                attach_logs: false,
              },
            },
            sessionIdFromURL: null,
            onSessionIdChange,
          }),
        {
          wrapper,
          initialProps: { jobId: 'job-new' },
        }
      );

      // Should initialize context because stored job_id doesn't match
      expect(mockStore._initializeContext).toHaveBeenCalledWith('job_code', {
        job_id: 'job-new',
        attach_code: false,
        attach_logs: false,
      });
    });
  });

  describe('Mode Switching', () => {
    it('should clear session when switching from job_code to workflow_template', () => {
      const { rerender } = renderHook(
        (props: { mode: 'job_code' | 'workflow_template' }) =>
          useAISession({
            isOpen: true,
            aiMode: {
              mode: props.mode,
              context:
                props.mode === 'job_code'
                  ? { job_id: 'job-1', attach_code: false, attach_logs: false }
                  : { project_id: 'proj-1', workflow_id: 'wf-1' },
            },
            sessionIdFromURL: null,
            onSessionIdChange,
          }),
        {
          wrapper,
          initialProps: { mode: 'job_code' as const },
        }
      );

      // Clear mocks after initial render
      vi.clearAllMocks();

      // Switch mode
      rerender({ mode: 'workflow_template' });

      // Should clear session
      expect(mockStore._clearSession).toHaveBeenCalled();
      expect(mockStore._clearSessionList).toHaveBeenCalled();
      expect(mockStore._setConnectionState).toHaveBeenCalledWith(
        'disconnected'
      );
      expect(onSessionIdChange).toHaveBeenCalledWith(null);
    });

    it('should do early return on mode change to let URL update propagate', () => {
      const { rerender } = renderHook(
        (props: { mode: 'job_code' | 'workflow_template' }) =>
          useAISession({
            isOpen: true,
            aiMode: {
              mode: props.mode,
              context:
                props.mode === 'job_code'
                  ? { job_id: 'job-1', attach_code: false, attach_logs: false }
                  : { project_id: 'proj-1', workflow_id: 'wf-1' },
            },
            sessionIdFromURL: null,
            onSessionIdChange,
          }),
        {
          wrapper,
          initialProps: { mode: 'job_code' as const },
        }
      );

      // Clear mocks after initial render
      vi.clearAllMocks();

      // Switch mode
      rerender({ mode: 'workflow_template' });

      // Should NOT call _initializeContext on mode change (early return)
      // The next render (after URL update) will initialize context
      expect(mockStore._initializeContext).not.toHaveBeenCalled();
    });
  });

  describe('Panel Close/Open', () => {
    it('should unsubscribe when panel closes', () => {
      const { rerender } = renderHook(
        (props: { isOpen: boolean }) =>
          useAISession({
            isOpen: props.isOpen,
            aiMode: {
              mode: 'job_code',
              context: {
                job_id: 'job-1',
                attach_code: false,
                attach_logs: false,
              },
            },
            sessionIdFromURL: 'session-123',
            onSessionIdChange,
          }),
        {
          wrapper,
          initialProps: { isOpen: true },
        }
      );

      // Clear mocks after initial render
      vi.clearAllMocks();

      // Close panel
      rerender({ isOpen: false });

      // Should unsubscribe immediately
      expect(mockUnsubscribeImmediate).toHaveBeenCalled();
    });

    it('should not subscribe when panel is closed', () => {
      renderHook(
        () =>
          useAISession({
            isOpen: false,
            aiMode: {
              mode: 'job_code',
              context: {
                job_id: 'job-1',
                attach_code: false,
                attach_logs: false,
              },
            },
            sessionIdFromURL: 'session-123',
            onSessionIdChange,
          }),
        { wrapper }
      );

      expect(mockSubscribe).not.toHaveBeenCalled();
    });
  });

  describe('Same subscription optimization', () => {
    it('should not re-subscribe if already subscribed to same topic', () => {
      const { rerender } = renderHook(
        () =>
          useAISession({
            isOpen: true,
            aiMode: {
              mode: 'job_code',
              context: {
                job_id: 'job-1',
                attach_code: false,
                attach_logs: false,
              },
            },
            sessionIdFromURL: 'session-123',
            onSessionIdChange,
          }),
        { wrapper }
      );

      const initialSubscribeCalls = mockSubscribe.mock.calls.length;

      // Re-render with same props
      rerender();

      // Should not call subscribe again
      expect(mockSubscribe.mock.calls.length).toBe(initialSubscribeCalls);
    });
  });
});
