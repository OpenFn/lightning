/**
 * TemplatePublishPanel Component Tests
 *
 * Tests for the template publishing panel that allows superusers to publish
 * workflows as templates or update existing templates.
 *
 * Test Coverage:
 * - Form validation (name required, max lengths)
 * - Publish flow success/failure
 * - Update vs create mode
 * - Tag parsing and removal
 * - Button disabled states
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { toast } from 'sonner';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { TemplatePublishPanel } from '../../../../js/collaborative-editor/components/inspector/TemplatePublishPanel';
import * as useChannelModule from '../../../../js/collaborative-editor/hooks/useChannel';
import * as useSessionModule from '../../../../js/collaborative-editor/hooks/useSession';
import * as useSessionContextModule from '../../../../js/collaborative-editor/hooks/useSessionContext';
import * as useWorkflowModule from '../../../../js/collaborative-editor/hooks/useWorkflow';
import {
  createMockWorkflowTemplate,
  createMockURLState,
  getURLStateMockValue,
} from '../../__helpers__';

// Mock Sonner (used by notifications)
vi.mock('sonner', () => ({
  toast: {
    info: vi.fn(),
    error: vi.fn(),
    success: vi.fn(),
    warning: vi.fn(),
    dismiss: vi.fn(),
  },
}));

// Mock useURLState
const urlState = createMockURLState();

vi.mock('../../../../js/react/lib/use-url-state', () => ({
  useURLState: () => getURLStateMockValue(urlState),
}));

// Mock channelRequest
vi.spyOn(useChannelModule, 'channelRequest');

// Mock useWorkflow hooks - needed for useAppForm which uses useValidation
vi.mock('../../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowState: vi.fn(),
  useWorkflowActions: vi.fn(() => ({
    setClientErrors: vi.fn(),
  })),
}));

// Mock hooks
const mockUseSession = vi.spyOn(useSessionModule, 'useSession');
const mockUseWorkflowTemplate = vi.spyOn(
  useSessionContextModule,
  'useWorkflowTemplate'
);
const mockUseWorkflowState = vi.mocked(useWorkflowModule.useWorkflowState);

// Mock channel
const createMockChannel = () => ({
  topic: 'workflow:w-1',
  on: vi.fn(),
  off: vi.fn(),
  push: vi.fn(),
});

// Mock workflow state factory
const createMockWorkflowState = () => ({
  workflow: { id: 'w-1', name: 'Test Workflow' },
  jobs: [
    {
      id: 'job-1',
      name: 'Test Job',
      adaptor: '@openfn/language-common@latest',
      body: 'fn(state => state)',
    },
  ],
  triggers: [{ id: 'trigger-1', type: 'webhook', enabled: true }],
  edges: [
    {
      id: 'edge-1',
      source_trigger_id: 'trigger-1',
      target_job_id: 'job-1',
      condition_type: 'always',
    },
  ],
  positions: { 'job-1': { x: 100, y: 100 } },
});

describe('TemplatePublishPanel', () => {
  let mockChannel: ReturnType<typeof createMockChannel>;
  let mockWorkflowState: ReturnType<typeof createMockWorkflowState>;

  beforeEach(() => {
    vi.clearAllMocks();
    urlState.reset();

    mockChannel = createMockChannel();
    mockWorkflowState = createMockWorkflowState();

    // Default mock implementations
    mockUseWorkflowState.mockImplementation(((selector: any) => {
      // Also include errors for form validation
      const stateWithErrors = {
        ...mockWorkflowState,
        workflow: { ...mockWorkflowState.workflow, errors: {} },
      };
      return selector(stateWithErrors);
    }) as any);

    mockUseWorkflowTemplate.mockReturnValue(null);

    mockUseSession.mockReturnValue({
      provider: { channel: mockChannel } as any,
      ydoc: null,
      awareness: null,
      userData: null,
      isConnected: true,
      isSynced: true,
      settled: true,
      lastStatus: null,
    });

    vi.mocked(useChannelModule.channelRequest).mockResolvedValue({});
  });

  describe('Create Mode', () => {
    test('pre-fills name with workflow name', () => {
      render(<TemplatePublishPanel />);

      const nameInput = screen.getByLabelText('Name');
      expect(nameInput).toHaveValue('Test Workflow');
    });

    test('starts with empty description and tags', () => {
      render(<TemplatePublishPanel />);

      const descriptionInput = screen.getByLabelText('Description');
      const tagsInput = screen.getByLabelText('Tags');

      expect(descriptionInput).toHaveValue('');
      expect(tagsInput).toHaveValue('');
    });

    test('renders Publish Template button', () => {
      render(<TemplatePublishPanel />);

      expect(
        screen.getByRole('button', { name: 'Publish Template' })
      ).toBeInTheDocument();
    });
  });

  describe('Update Mode', () => {
    beforeEach(() => {
      mockUseWorkflowTemplate.mockReturnValue(
        createMockWorkflowTemplate({
          name: 'Existing Template',
          description: 'Template description',
          tags: ['tag1', 'tag2'],
        })
      );
    });

    test('pre-fills form from existing template', () => {
      render(<TemplatePublishPanel />);

      const nameInput = screen.getByLabelText('Name');
      const descriptionInput = screen.getByLabelText('Description');
      const tagsInput = screen.getByLabelText('Tags');

      expect(nameInput).toHaveValue('Existing Template');
      expect(descriptionInput).toHaveValue('Template description');
      expect(tagsInput).toHaveValue('tag1, tag2');
    });

    test('renders Update Template button', () => {
      render(<TemplatePublishPanel />);

      expect(
        screen.getByRole('button', { name: 'Update Template' })
      ).toBeInTheDocument();
    });

    test('displays existing tags as removable chips', () => {
      render(<TemplatePublishPanel />);

      // Check tags are displayed as chips
      expect(screen.getByText('tag1')).toBeInTheDocument();
      expect(screen.getByText('tag2')).toBeInTheDocument();

      // Check remove buttons are present
      expect(
        screen.getByRole('button', { name: 'Remove tag1 tag' })
      ).toBeInTheDocument();
      expect(
        screen.getByRole('button', { name: 'Remove tag2 tag' })
      ).toBeInTheDocument();
    });
  });

  describe('Form Validation', () => {
    test('shows required error when name is empty', async () => {
      const user = userEvent.setup();
      render(<TemplatePublishPanel />);

      const nameInput = screen.getByLabelText('Name');

      // Clear the name field
      await user.clear(nameInput);

      // Error message should be shown
      await waitFor(() => {
        expect(screen.getByText('Name is required')).toBeInTheDocument();
      });
    });

    test('shows error when name exceeds 255 characters', async () => {
      const user = userEvent.setup();
      render(<TemplatePublishPanel />);

      const nameInput = screen.getByLabelText('Name');
      const longName = 'a'.repeat(256);

      // Use paste instead of type to avoid timeout on CI (256 keystrokes is slow)
      await user.clear(nameInput);
      await user.paste(longName);

      await waitFor(() => {
        expect(
          screen.getByText('Name must be less than 255 characters')
        ).toBeInTheDocument();
      });
    });

    test('shows error when description exceeds 1000 characters', async () => {
      const user = userEvent.setup();
      render(<TemplatePublishPanel />);

      const descriptionInput = screen.getByLabelText('Description');
      const longDescription = 'a'.repeat(1001);

      // Use paste instead of type for large text to avoid timeout on CI
      await user.click(descriptionInput);
      await user.paste(longDescription);

      await waitFor(() => {
        expect(
          screen.getByText('Description must be less than 1000 characters')
        ).toBeInTheDocument();
      });
    });
  });

  describe('Tag Management', () => {
    test('parses comma-separated tags and trims whitespace', async () => {
      const user = userEvent.setup();
      render(<TemplatePublishPanel />);

      const tagsInput = screen.getByLabelText('Tags');
      // Use clear + paste to prevent state leak from previous tests
      await user.clear(tagsInput);
      await user.paste('tag1, tag2 , tag3');

      // Tags should be displayed as chips
      await waitFor(() => {
        expect(screen.getByText('tag1')).toBeInTheDocument();
        expect(screen.getByText('tag2')).toBeInTheDocument();
        expect(screen.getByText('tag3')).toBeInTheDocument();
      });
    });

    test('removes tag when X button clicked', async () => {
      const user = userEvent.setup();
      mockUseWorkflowTemplate.mockReturnValue(
        createMockWorkflowTemplate({
          tags: ['keep', 'remove'],
        })
      );

      render(<TemplatePublishPanel />);

      // Verify both tags exist
      expect(screen.getByText('keep')).toBeInTheDocument();
      expect(screen.getByText('remove')).toBeInTheDocument();

      // Click remove button for 'remove' tag
      const removeButton = screen.getByRole('button', {
        name: 'Remove remove tag',
      });
      await user.click(removeButton);

      // Tag should be removed
      await waitFor(() => {
        expect(screen.queryByText('remove')).not.toBeInTheDocument();
      });
      expect(screen.getByText('keep')).toBeInTheDocument();
    });

    test('filters out empty tags', async () => {
      const user = userEvent.setup();
      render(<TemplatePublishPanel />);

      const tagsInput = screen.getByLabelText('Tags');
      // Use clear + paste to prevent state leak from previous tests
      await user.clear(tagsInput);
      await user.paste('tag1,,tag2, ,tag3');

      // Only non-empty tags should be displayed
      await waitFor(() => {
        expect(screen.getByText('tag1')).toBeInTheDocument();
        expect(screen.getByText('tag2')).toBeInTheDocument();
        expect(screen.getByText('tag3')).toBeInTheDocument();
      });
    });
  });

  describe('Publish Flow', () => {
    test('calls channelRequest with correct payload on publish', async () => {
      const user = userEvent.setup();
      render(<TemplatePublishPanel />);

      const publishButton = screen.getByRole('button', {
        name: 'Publish Template',
      });
      await user.click(publishButton);

      await waitFor(() => {
        expect(useChannelModule.channelRequest).toHaveBeenCalledWith(
          mockChannel,
          'publish_template',
          expect.objectContaining({
            name: 'Test Workflow',
            description: undefined,
            tags: [],
            code: expect.any(String),
            positions: { 'job-1': { x: 100, y: 100 } },
          })
        );
      });
    });

    test('disables all triggers when publishing template', async () => {
      const user = userEvent.setup();
      // Mock a workflow with an enabled trigger
      mockWorkflowState.triggers = [
        { id: 'trigger-1', type: 'webhook', enabled: true },
      ];

      render(<TemplatePublishPanel />);

      const publishButton = screen.getByRole('button', {
        name: 'Publish Template',
      });
      await user.click(publishButton);

      await waitFor(() => {
        expect(useChannelModule.channelRequest).toHaveBeenCalled();
      });

      // Extract the code from the call
      const call = vi.mocked(useChannelModule.channelRequest).mock.calls[0];
      const payload = call[2] as any;
      const yamlCode = payload.code;

      // Verify the YAML contains enabled: false for the trigger
      expect(yamlCode).toContain('enabled: false');
      expect(yamlCode).not.toContain('enabled: true');
    });

    test('shows success notification and navigates on success', async () => {
      const user = userEvent.setup();
      render(<TemplatePublishPanel />);

      const publishButton = screen.getByRole('button', {
        name: 'Publish Template',
      });
      await user.click(publishButton);

      await waitFor(() => {
        expect(toast.info).toHaveBeenCalledWith(
          'Workflow published as template',
          expect.objectContaining({
            description: 'Your workflow is now available as a template',
          })
        );
      });

      expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
        panel: 'code',
      });
    });

    test('shows update success notification in update mode', async () => {
      const user = userEvent.setup();
      mockUseWorkflowTemplate.mockReturnValue(
        createMockWorkflowTemplate({ name: 'Existing Template' })
      );

      render(<TemplatePublishPanel />);

      const updateButton = screen.getByRole('button', {
        name: 'Update Template',
      });
      await user.click(updateButton);

      await waitFor(() => {
        expect(toast.info).toHaveBeenCalledWith(
          'Template updated',
          expect.objectContaining({
            description: 'Your changes have been saved',
          })
        );
      });
    });

    test('shows error notification on channel error', async () => {
      const user = userEvent.setup();
      vi.mocked(useChannelModule.channelRequest).mockRejectedValue(
        new Error('Publish failed')
      );

      render(<TemplatePublishPanel />);

      const publishButton = screen.getByRole('button', {
        name: 'Publish Template',
      });
      await user.click(publishButton);

      await waitFor(() => {
        expect(toast.error).toHaveBeenCalledWith(
          'Failed to publish template',
          expect.objectContaining({
            description: 'Publish failed',
          })
        );
      });
    });

    test('shows error when channel not connected', async () => {
      const user = userEvent.setup();
      mockUseSession.mockReturnValue({
        provider: null,
        ydoc: null,
        awareness: null,
        userData: null,
        isConnected: false,
        isSynced: false,
        settled: false,
        lastStatus: null,
      });

      render(<TemplatePublishPanel />);

      const publishButton = screen.getByRole('button', {
        name: 'Publish Template',
      });
      await user.click(publishButton);

      await waitFor(() => {
        expect(toast.error).toHaveBeenCalledWith(
          'Cannot publish template',
          expect.objectContaining({
            description: 'Channel not connected or workflow not saved',
          })
        );
      });
    });
  });

  describe('Button Disabled States', () => {
    test('disables publish button during publishing', async () => {
      const user = userEvent.setup();

      // Create a promise we can control
      let resolvePublish: () => void;
      const publishPromise = new Promise<void>(resolve => {
        resolvePublish = resolve;
      });
      vi.mocked(useChannelModule.channelRequest).mockReturnValue(
        publishPromise as any
      );

      render(<TemplatePublishPanel />);

      const publishButton = screen.getByRole('button', {
        name: 'Publish Template',
      });
      await user.click(publishButton);

      // Button should show "Publishing..." and be disabled
      await waitFor(() => {
        expect(
          screen.getByRole('button', { name: 'Publishing...' })
        ).toBeDisabled();
      });

      // Resolve the promise
      resolvePublish!();
    });

    test('disables form fields during publishing', async () => {
      const user = userEvent.setup();

      let resolvePublish: () => void;
      const publishPromise = new Promise<void>(resolve => {
        resolvePublish = resolve;
      });
      vi.mocked(useChannelModule.channelRequest).mockReturnValue(
        publishPromise as any
      );

      render(<TemplatePublishPanel />);

      const publishButton = screen.getByRole('button', {
        name: 'Publish Template',
      });
      await user.click(publishButton);

      // Form fields should be disabled
      await waitFor(() => {
        expect(screen.getByLabelText('Name')).toBeDisabled();
        expect(screen.getByLabelText('Description')).toBeDisabled();
        expect(screen.getByLabelText('Tags')).toBeDisabled();
      });

      // Resolve the promise
      resolvePublish!();
    });

    test('disables Back button during publishing', async () => {
      const user = userEvent.setup();

      let resolvePublish: () => void;
      const publishPromise = new Promise<void>(resolve => {
        resolvePublish = resolve;
      });
      vi.mocked(useChannelModule.channelRequest).mockReturnValue(
        publishPromise as any
      );

      render(<TemplatePublishPanel />);

      const publishButton = screen.getByRole('button', {
        name: 'Publish Template',
      });
      await user.click(publishButton);

      await waitFor(() => {
        expect(screen.getByRole('button', { name: 'Back' })).toBeDisabled();
      });

      resolvePublish!();
    });

    test('re-enables form after error', async () => {
      const user = userEvent.setup();
      vi.mocked(useChannelModule.channelRequest).mockRejectedValue(
        new Error('Publish failed')
      );

      render(<TemplatePublishPanel />);

      const publishButton = screen.getByRole('button', {
        name: 'Publish Template',
      });
      await user.click(publishButton);

      // Wait for error and re-enable
      await waitFor(() => {
        expect(
          screen.getByRole('button', { name: 'Publish Template' })
        ).not.toBeDisabled();
      });

      expect(screen.getByLabelText('Name')).not.toBeDisabled();
    });
  });

  describe('Navigation', () => {
    test('Back button navigates to code panel', async () => {
      const user = userEvent.setup();
      render(<TemplatePublishPanel />);

      const backButton = screen.getByRole('button', { name: 'Back' });
      await user.click(backButton);

      expect(urlState.mockFns.updateSearchParams).toHaveBeenCalledWith({
        panel: 'code',
      });
    });
  });
});
