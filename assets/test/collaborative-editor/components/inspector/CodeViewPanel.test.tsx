/**
 * CodeViewPanel Component Tests
 *
 * Tests for CodeViewPanel component that displays workflow as YAML code
 * and provides template publishing functionality.
 *
 * Test coverage:
 * - YAML generation from workflow state
 * - Loading states
 * - Error handling for YAML generation failures
 * - Template publishing button visibility and state
 * - Button text based on template existence
 * - Tooltip messages for different states
 * - Click handler for opening publish panel
 * - Button styling based on enabled/disabled state
 *
 * Note: Download and copy functionality require manual testing due to jsdom
 * limitations with DOM manipulation and clipboard API.
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import YAML from 'yaml';

import { CodeViewPanel } from '../../../../js/collaborative-editor/components/inspector/CodeViewPanel';
import { useURLState } from '../../../../js/react/lib/use-url-state';
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
  useCanPublishTemplate: vi.fn(() => {
    // Calculate based on current mock state
    const hasUnsavedChanges =
      mockWorkflowState.workflow?.lock_version !==
      mockLatestSnapshotLockVersion;

    return {
      canPublish: mockUser.support_user,
      buttonDisabled: hasUnsavedChanges,
      tooltipMessage: hasUnsavedChanges
        ? `You must save your workflow first before ${mockWorkflowTemplate ? 'updating' : 'publishing'} a template.`
        : '',
      buttonText: mockWorkflowTemplate ? 'Update Template' : 'Publish Template',
    };
  }),
}));

// Mock state for useSessionContext hooks
const mockUser = {
  id: 'test-user-id',
  email: 'test@example.com',
  first_name: 'Test',
  last_name: 'User',
  email_confirmed: true,
  support_user: true, // Make user a superuser for template functionality
  inserted_at: '2024-01-01T00:00:00Z',
};

let mockWorkflowTemplate: any = null;
let mockLatestSnapshotLockVersion = 1;

// Helper functions for tests to manipulate session context mocks
const setMockUser = (newUser: any) => {
  Object.assign(mockUser, newUser);
};

const resetMockUser = () => {
  mockUser.id = 'test-user-id';
  mockUser.email = 'test@example.com';
  mockUser.first_name = 'Test';
  mockUser.last_name = 'User';
  mockUser.email_confirmed = true;
  mockUser.support_user = true;
  mockUser.inserted_at = '2024-01-01T00:00:00Z';
};

const setMockWorkflowTemplate = (template: any) => {
  mockWorkflowTemplate = template;
};

const setMockLatestSnapshotLockVersion = (version: number) => {
  mockLatestSnapshotLockVersion = version;
};

const resetSessionContextMocks = () => {
  resetMockUser();
  mockWorkflowTemplate = null;
  mockLatestSnapshotLockVersion = 1;
};

// Mock useSessionContext hooks
vi.mock('../../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useUser: vi.fn(() => mockUser),
  useWorkflowTemplate: vi.fn(() => mockWorkflowTemplate),
  useLatestSnapshotLockVersion: vi.fn(() => mockLatestSnapshotLockVersion),
}));

// Mock useURLState hook
const mockUpdateSearchParams = vi.fn();
const mockGetSearchParam = vi.fn();

vi.mock('../../../../js/react/lib/use-url-state', () => ({
  useURLState: vi.fn(() => ({
    updateSearchParams: mockUpdateSearchParams,
    getSearchParam: mockGetSearchParam,
  })),
}));

describe('CodeViewPanel', () => {
  beforeEach(() => {
    // Reset all mocks
    vi.clearAllMocks();

    // Reset workflow state
    resetMockWorkflowState();

    // Reset session context mocks
    resetSessionContextMocks();
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

  describe('template publishing button', () => {
    beforeEach(() => {
      // Need a workflow to be loaded for button to show
      setMockWorkflowState({
        workflow: { id: 'w1', name: 'Test Workflow', lock_version: 1 },
      });
    });

    test('renders publish template button when user is superuser', () => {
      setMockUser({ support_user: true });
      render(<CodeViewPanel />);
      expect(
        screen.getByRole('button', { name: /publish template/i })
      ).toBeInTheDocument();
    });

    test('hides publish template button when user is not superuser', () => {
      setMockUser({ support_user: false });
      render(<CodeViewPanel />);
      expect(
        screen.queryByRole('button', { name: /publish template/i })
      ).not.toBeInTheDocument();
    });

    test('disables button when workflow has unsaved changes', () => {
      // Workflow lock_version is 1, but latest snapshot is 2
      setMockLatestSnapshotLockVersion(2);
      render(<CodeViewPanel />);

      const button = screen.getByRole('button', { name: /publish template/i });
      expect(button).toBeDisabled();
    });

    test('enables button when workflow is saved and user is superuser', () => {
      // Lock versions match - no unsaved changes
      setMockLatestSnapshotLockVersion(1);
      setMockUser({ support_user: true });
      render(<CodeViewPanel />);

      const button = screen.getByRole('button', { name: /publish template/i });
      expect(button).toBeEnabled();
    });

    test('shows "Publish Template" text when no template exists', () => {
      setMockWorkflowTemplate(null);
      render(<CodeViewPanel />);

      expect(
        screen.getByRole('button', { name: /publish template/i })
      ).toBeInTheDocument();
    });

    test('shows "Update Template" text when template exists', () => {
      setMockWorkflowTemplate({ id: 'template-1', name: 'Existing Template' });
      render(<CodeViewPanel />);

      expect(
        screen.getByRole('button', { name: /update template/i })
      ).toBeInTheDocument();
    });

    test('shows tooltip about unsaved changes when workflow is not saved', () => {
      setMockLatestSnapshotLockVersion(2);
      setMockWorkflowTemplate(null);
      render(<CodeViewPanel />);

      const button = screen.getByRole('button', { name: /publish template/i });
      expect(button).toHaveAttribute(
        'title',
        'You must save your workflow first before publishing a template.'
      );
    });

    test('shows tooltip about unsaved changes for updating when template exists', () => {
      setMockLatestSnapshotLockVersion(2);
      setMockWorkflowTemplate({ id: 'template-1', name: 'Existing Template' });
      render(<CodeViewPanel />);

      const button = screen.getByRole('button', { name: /update template/i });
      expect(button).toHaveAttribute(
        'title',
        'You must save your workflow first before updating a template.'
      );
    });

    test('no tooltip shown when button is enabled', () => {
      setMockLatestSnapshotLockVersion(1); // No unsaved changes
      setMockUser({ support_user: true });
      render(<CodeViewPanel />);

      const button = screen.getByRole('button', { name: /publish template/i });
      // When enabled, title attribute should not be present (tooltip is undefined)
      expect(button).not.toHaveAttribute('title');
    });

    test('calls updateSearchParams with publish-template panel on click', async () => {
      const user = userEvent.setup();
      setMockLatestSnapshotLockVersion(1); // No unsaved changes
      render(<CodeViewPanel />);

      const button = screen.getByRole('button', { name: /publish template/i });
      await user.click(button);

      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        panel: 'publish-template',
      });
    });

    test('does not call updateSearchParams when button is disabled', async () => {
      const user = userEvent.setup();
      setMockLatestSnapshotLockVersion(2); // Unsaved changes
      render(<CodeViewPanel />);

      const button = screen.getByRole('button', { name: /publish template/i });
      // Button is disabled, click should not trigger handler
      await user.click(button);

      expect(mockUpdateSearchParams).not.toHaveBeenCalled();
    });

    test('button has correct styling when enabled', () => {
      setMockLatestSnapshotLockVersion(1); // No unsaved changes
      render(<CodeViewPanel />);

      const button = screen.getByRole('button', { name: /publish template/i });
      expect(button).toHaveClass('bg-primary-600');
      expect(button).toHaveClass('hover:bg-primary-700');
      expect(button).not.toHaveClass('cursor-not-allowed');
    });

    test('button has correct styling when disabled', () => {
      setMockLatestSnapshotLockVersion(2); // Unsaved changes
      render(<CodeViewPanel />);

      const button = screen.getByRole('button', { name: /publish template/i });
      expect(button).toHaveClass('bg-primary-300');
      expect(button).toHaveClass('cursor-not-allowed');
    });
  });
});
