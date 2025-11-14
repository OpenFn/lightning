/**
 * Tests for navigation utilities
 *
 * These utilities provide clean, testable navigation functions that build URLs
 * from IDs rather than parsing existing URLs.
 */

import { describe, expect, test, vi, beforeEach, afterEach } from 'vitest';

import {
  navigateToRun,
  navigateToWorkOrderHistory,
  navigateToWorkflowHistory,
} from '../../../js/collaborative-editor/utils/navigation';

describe('navigation utilities', () => {
  // Save original window.location
  const originalLocation = window.location;

  beforeEach(() => {
    // Mock window.location
    delete (window as any).location;
    window.location = {
      ...originalLocation,
      origin: 'https://example.com',
      assign: vi.fn(),
    } as any;
  });

  afterEach(() => {
    // Restore original window.location
    window.location = originalLocation;
    vi.restoreAllMocks();
  });

  describe('navigateToWorkflowHistory', () => {
    test('builds correct URL with project and workflow IDs', () => {
      const projectId = 'proj-123';
      const workflowId = 'wf-456';

      navigateToWorkflowHistory(projectId, workflowId);

      expect(window.location.assign).toHaveBeenCalledWith(
        'https://example.com/projects/proj-123/history?filters%5Bworkflow_id%5D=wf-456'
      );
    });

    test('uses URLSearchParams for query string encoding', () => {
      const projectId = 'proj-123';
      const workflowId = 'wf-with-special-chars-&-=';

      navigateToWorkflowHistory(projectId, workflowId);

      const assignCall = vi.mocked(window.location.assign).mock.calls[0][0];
      const url = new URL(assignCall);

      // Verify URLSearchParams encoded the special characters
      expect(url.searchParams.get('filters[workflow_id]')).toBe(
        'wf-with-special-chars-&-='
      );
    });

    test('constructs clean pathname from origin', () => {
      const projectId = 'proj-123';
      const workflowId = 'wf-456';

      navigateToWorkflowHistory(projectId, workflowId);

      const assignCall = vi.mocked(window.location.assign).mock.calls[0][0];
      const url = new URL(assignCall);

      expect(url.origin).toBe('https://example.com');
      expect(url.pathname).toBe('/projects/proj-123/history');
    });
  });

  describe('navigateToWorkOrderHistory', () => {
    test('builds correct URL with project and work order IDs', () => {
      const projectId = 'proj-abc';
      const workOrderId = 'wo-xyz';

      navigateToWorkOrderHistory(projectId, workOrderId);

      expect(window.location.assign).toHaveBeenCalledWith(
        'https://example.com/projects/proj-abc/history?filters%5Bworkorder_id%5D=wo-xyz'
      );
    });

    test('uses correct filter parameter name', () => {
      const projectId = 'proj-123';
      const workOrderId = 'wo-456';

      navigateToWorkOrderHistory(projectId, workOrderId);

      const assignCall = vi.mocked(window.location.assign).mock.calls[0][0];
      const url = new URL(assignCall);

      // Should use 'workorder_id' not 'workflow_id'
      expect(url.searchParams.get('filters[workorder_id]')).toBe('wo-456');
      expect(url.searchParams.has('filters[workflow_id]')).toBe(false);
    });

    test('handles UUID format correctly', () => {
      const projectId = '550e8400-e29b-41d4-a716-446655440000';
      const workOrderId = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

      navigateToWorkOrderHistory(projectId, workOrderId);

      const assignCall = vi.mocked(window.location.assign).mock.calls[0][0];
      const url = new URL(assignCall);

      expect(url.pathname).toBe(
        '/projects/550e8400-e29b-41d4-a716-446655440000/history'
      );
      expect(url.searchParams.get('filters[workorder_id]')).toBe(
        '6ba7b810-9dad-11d1-80b4-00c04fd430c8'
      );
    });
  });

  describe('navigateToRun', () => {
    test('builds correct URL with project and run IDs', () => {
      const projectId = 'proj-123';
      const runId = 'run-789';

      navigateToRun(projectId, runId);

      expect(window.location.assign).toHaveBeenCalledWith(
        'https://example.com/projects/proj-123/runs/run-789'
      );
    });

    test('does not include query parameters', () => {
      const projectId = 'proj-123';
      const runId = 'run-456';

      navigateToRun(projectId, runId);

      const assignCall = vi.mocked(window.location.assign).mock.calls[0][0];
      const url = new URL(assignCall);

      expect(url.search).toBe('');
      expect(url.pathname).toBe('/projects/proj-123/runs/run-456');
    });

    test('constructs pathname correctly', () => {
      const projectId = 'proj-abc';
      const runId = 'run-xyz';

      navigateToRun(projectId, runId);

      const assignCall = vi.mocked(window.location.assign).mock.calls[0][0];
      const url = new URL(assignCall);

      // Should be /projects/:projectId/runs/:runId
      expect(url.pathname).toBe('/projects/proj-abc/runs/run-xyz');
    });

    test('handles UUID format correctly', () => {
      const projectId = '550e8400-e29b-41d4-a716-446655440000';
      const runId = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

      navigateToRun(projectId, runId);

      const assignCall = vi.mocked(window.location.assign).mock.calls[0][0];

      expect(assignCall).toBe(
        'https://example.com/projects/550e8400-e29b-41d4-a716-446655440000/runs/6ba7b810-9dad-11d1-80b4-00c04fd430c8'
      );
    });
  });

  describe('integration scenarios', () => {
    test('all functions use window.location.assign for navigation', () => {
      navigateToWorkflowHistory('p1', 'w1');
      navigateToWorkOrderHistory('p1', 'wo1');
      navigateToRun('p1', 'r1');

      expect(window.location.assign).toHaveBeenCalledTimes(3);
    });

    test('all functions build absolute URLs', () => {
      navigateToWorkflowHistory('p1', 'w1');
      const call1 = vi.mocked(window.location.assign).mock.calls[0][0];

      navigateToWorkOrderHistory('p1', 'wo1');
      const call2 = vi.mocked(window.location.assign).mock.calls[1][0];

      navigateToRun('p1', 'r1');
      const call3 = vi.mocked(window.location.assign).mock.calls[2][0];

      // All should start with the origin
      expect(call1).toMatch(/^https:\/\/example\.com\//);
      expect(call2).toMatch(/^https:\/\/example\.com\//);
      expect(call3).toMatch(/^https:\/\/example\.com\//);
    });
  });
});
