/**
 * CodeViewPanel Component Tests
 *
 * Tests for CodeViewPanel component that displays workflow as YAML code.
 * Focuses on core YAML generation and error handling logic.
 *
 * Test coverage:
 * - YAML generation from workflow state
 * - Loading states
 * - Error handling for YAML generation failures
 *
 * Note: Download and copy functionality require manual testing due to jsdom
 * limitations with DOM manipulation and clipboard API.
 */

import { render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import YAML from 'yaml';

import { CodeViewPanel } from '../../../../js/collaborative-editor/components/inspector/CodeViewPanel';
import * as yamlUtil from '../../../../js/yaml/util';

// Mock yaml/util with simple pass-through
vi.mock('../../../../js/yaml/util', () => ({
  convertWorkflowStateToSpec: vi.fn((workflowState: any) => ({
    name: workflowState.name,
    jobs: workflowState.jobs || [],
    triggers: workflowState.triggers || [],
    edges: workflowState.edges || [],
  })),
}));

// Mock useWorkflowState hook with state management
const mockWorkflowState = {
  workflow: null as any,
  jobs: [] as any[],
  triggers: [] as any[],
  edges: [] as any[],
  positions: {} as any,
};

// Helper functions for tests to manipulate mock state
const setMockWorkflowState = (newState: any) => {
  Object.assign(mockWorkflowState, newState);
};

const resetMockWorkflowState = () => {
  mockWorkflowState.workflow = null;
  mockWorkflowState.jobs = [];
  mockWorkflowState.triggers = [];
  mockWorkflowState.edges = [];
  mockWorkflowState.positions = {};
};

vi.mock('../../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowState: vi.fn((selector: any) => {
    // Dynamically read from mockWorkflowState to ensure fresh reads
    const state = {
      workflow: mockWorkflowState.workflow,
      jobs: mockWorkflowState.jobs,
      triggers: mockWorkflowState.triggers,
      edges: mockWorkflowState.edges,
      positions: mockWorkflowState.positions,
    };
    return selector(state);
  }),
}));

describe('CodeViewPanel', () => {
  beforeEach(() => {
    // Reset all mocks
    vi.clearAllMocks();

    // Reset workflow state
    resetMockWorkflowState();
  });

  describe('rendering and YAML generation', () => {
    test('displays loading state when workflow is missing', async () => {
      // Workflow state defaults to null
      render(<CodeViewPanel />);

      expect(screen.getByText('Loading...')).toBeInTheDocument();
    });

    test('generates and displays workflow YAML with correct structure', async () => {
      setMockWorkflowState({
        workflow: { id: 'w1', name: 'Test Workflow' },
        jobs: [
          {
            id: 'j1',
            name: 'Test Job',
            adaptor: '@openfn/language-http@latest',
            body: 'fn(state => state)',
          },
        ],
        triggers: [{ id: 't1', type: 'webhook', enabled: true }],
        edges: [
          {
            id: 'e1',
            source_trigger_id: 't1',
            target_job_id: 'j1',
            condition_type: 'always',
            enabled: true,
          },
        ],
      });

      render(<CodeViewPanel />);

      const textarea = screen.getByRole('textbox', {
        name: /workflow yaml code/i,
      }) as HTMLTextAreaElement;

      // Verify YAML is displayed
      expect(textarea).toBeInTheDocument();
      expect(textarea.value).toContain('Test Workflow');
      expect(textarea.value).toBeTruthy();

      // Verify it's valid YAML
      expect(() => YAML.parse(textarea.value)).not.toThrow();
    });

    test('handles YAML generation errors gracefully', () => {
      const consoleErrorSpy = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {});

      vi.mocked(yamlUtil.convertWorkflowStateToSpec).mockImplementationOnce(
        () => {
          throw new Error('YAML generation failed');
        }
      );

      setMockWorkflowState({
        workflow: { id: 'w1', name: 'Test' },
        jobs: [],
      });

      render(<CodeViewPanel />);

      const textarea = screen.getByRole('textbox') as HTMLTextAreaElement;
      expect(textarea.value).toContain('# Error generating YAML');

      consoleErrorSpy.mockRestore();
    });
  });
});
