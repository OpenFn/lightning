/**
 * useAIMode - Tests for AI mode detection hook
 *
 * Tests the hook that determines whether to use job_code or workflow_template mode
 * based on URL parameters and workflow state.
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { renderHook } from '@testing-library/react';

import { useAIMode } from '../../../js/collaborative-editor/hooks/useAIMode';
import { createMockURLState, getURLStateMockValue } from '../__helpers__';

// Create centralized URL state mock
const urlState = createMockURLState();

// Mock dependencies
vi.mock('../../../js/react/lib/use-url-state', () => ({
  useURLState: () => getURLStateMockValue(urlState),
}));

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useProject: vi.fn(),
}));

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowState: vi.fn(),
}));

import { useProject } from '../../../js/collaborative-editor/hooks/useSessionContext';
import { useWorkflowState } from '../../../js/collaborative-editor/hooks/useWorkflow';

describe('useAIMode', () => {
  const mockProject = { id: 'project-123', name: 'Test Project' };
  const mockWorkflow = { id: 'workflow-123', name: 'Test Workflow' };

  beforeEach(() => {
    vi.clearAllMocks();
    urlState.reset();

    // Default mocks
    vi.mocked(useProject).mockReturnValue(mockProject as any);

    // Mock useWorkflowState to handle selector function
    vi.mocked(useWorkflowState).mockImplementation((selector: any) => {
      const state = {
        workflow: mockWorkflow,
        jobs: [],
      };
      return selector ? selector(state) : state;
    });
  });

  describe('Workflow Template Mode', () => {
    it('should return workflow_template mode by default', () => {
      const { result } = renderHook(() => useAIMode());

      expect(result.current).toEqual({
        mode: 'workflow_template',
        page: 'workflow_template',
        context: {
          project_id: 'project-123',
          workflow_id: 'workflow-123',
        },
        storageKey: 'ai-workflow-workflow-123',
      });
    });

    it('should use project storage key when no workflow exists', () => {
      vi.mocked(useWorkflowState).mockImplementation((selector: any) => {
        const state = { workflow: null, jobs: [] };
        return selector ? selector(state) : state;
      });

      const { result } = renderHook(() => useAIMode());

      expect(result.current).toEqual({
        mode: 'workflow_template',
        page: 'workflow_template',
        context: {
          project_id: 'project-123',
        },
        storageKey: 'ai-project-project-123',
      });
    });

    it('should return null when no project exists', () => {
      vi.mocked(useProject).mockReturnValue(null);

      const { result } = renderHook(() => useAIMode());

      expect(result.current).toBeNull();
    });
  });

  describe('Job Code Mode', () => {
    beforeEach(() => {
      urlState.setParams({ panel: 'editor', job: 'job-456' });
    });

    it('should return job_code page when IDE is open', () => {
      const { result } = renderHook(() => useAIMode());

      expect(result.current).toEqual({
        mode: 'workflow_template',
        page: 'job_code',
        context: {
          project_id: 'project-123',
          workflow_id: 'workflow-123',
          job_id: 'job-456',
          attach_code: false,
          attach_logs: false,
        },
        storageKey: 'ai-workflow-workflow-123',
      });
    });

    it('should include job data when job exists in Y.Doc', () => {
      const mockJob = {
        id: 'job-456',
        name: 'Test Job',
        body: 'fn(state => state);',
        adaptor: '@openfn/language-common@latest',
      };

      vi.mocked(useWorkflowState).mockImplementation((selector: any) => {
        const state = {
          workflow: mockWorkflow,
          jobs: [mockJob],
        };
        return selector ? selector(state) : state;
      });

      const { result } = renderHook(() => useAIMode());

      expect(result.current?.context).toEqual({
        project_id: 'project-123',
        workflow_id: 'workflow-123',
        job_id: 'job-456',
        attach_code: false,
        attach_logs: false,
        job_name: 'Test Job',
        job_body: 'fn(state => state);',
        job_adaptor: '@openfn/language-common@latest',
      });
    });

    it('should handle unsaved jobs without Y.Doc data', () => {
      vi.mocked(useWorkflowState).mockImplementation((selector: any) => {
        const state = {
          workflow: mockWorkflow,
          jobs: [], // No jobs in Y.Doc yet
        };
        return selector ? selector(state) : state;
      });

      const { result } = renderHook(() => useAIMode());

      expect(result.current?.context).toEqual({
        project_id: 'project-123',
        workflow_id: 'workflow-123',
        job_id: 'job-456',
        attach_code: false,
        attach_logs: false,
        // No job_name, job_body, job_adaptor for unsaved job
      });
    });

    it('should include follow_run_id when run parameter exists', () => {
      urlState.setParam('run', 'run-789');

      const { result } = renderHook(() => useAIMode());

      expect(result.current?.context).toMatchObject({
        job_id: 'job-456',
        follow_run_id: 'run-789',
      });
    });

    it('should not include workflow_id when workflow is null', () => {
      vi.mocked(useWorkflowState).mockImplementation((selector: any) => {
        const state = {
          workflow: null,
          jobs: [],
        };
        return selector ? selector(state) : state;
      });

      const { result } = renderHook(() => useAIMode());

      expect(result.current?.context).toHaveProperty('project_id');
      expect(result.current?.context).not.toHaveProperty('workflow_id');
    });

    it('should only activate when panel=editor', () => {
      urlState.clearParams();
      urlState.setParams({ panel: 'inspector', job: 'job-456' });

      const { result } = renderHook(() => useAIMode());

      // Should fall back to workflow_template mode
      expect(result.current?.mode).toBe('workflow_template');
    });

    it('should only activate when job parameter exists', () => {
      urlState.clearParams();
      urlState.setParam('panel', 'editor');

      const { result } = renderHook(() => useAIMode());

      // Should fall back to workflow_template mode
      expect(result.current?.mode).toBe('workflow_template');
    });
  });

  describe('Page Changes', () => {
    it('should change page when URL params change', () => {
      const { result, rerender } = renderHook(() => useAIMode());

      const firstResult = result.current;
      expect(firstResult?.mode).toBe('workflow_template');
      expect(firstResult?.page).toBe('workflow_template');

      // Change URL params to trigger job code page
      urlState.setParams({ panel: 'editor', job: 'job-456' });

      rerender();
      const secondResult = result.current;

      expect(secondResult?.mode).toBe('workflow_template');
      expect(secondResult?.page).toBe('job_code');
      expect(firstResult).not.toEqual(secondResult);
    });
  });

  describe('Storage Keys', () => {
    it('should use workflow storage key even when on job page', () => {
      urlState.setParams({ panel: 'editor', job: 'job-unique-id' });

      const { result } = renderHook(() => useAIMode());

      // Storage key is based on workflow/project, not job
      expect(result.current?.storageKey).toBe('ai-workflow-workflow-123');
      expect(result.current?.page).toBe('job_code');
    });

    it('should generate correct storage key for workflow mode with workflow', () => {
      const { result } = renderHook(() => useAIMode());

      expect(result.current?.storageKey).toBe('ai-workflow-workflow-123');
    });

    it('should generate correct storage key for workflow mode without workflow', () => {
      vi.mocked(useWorkflowState).mockImplementation((selector: any) => {
        const state = { workflow: null, jobs: [] };
        return selector ? selector(state) : state;
      });

      const { result } = renderHook(() => useAIMode());

      expect(result.current?.storageKey).toBe('ai-project-project-123');
    });
  });
});
