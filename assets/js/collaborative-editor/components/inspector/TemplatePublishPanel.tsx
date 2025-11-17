import { useMemo, useState } from 'react';
import { z } from 'zod';
import YAML from 'yaml';
import { useAppForm } from '#/collaborative-editor/components/form';
import { createZodValidator } from '#/collaborative-editor/components/form/createZodValidator';
import { useWorkflowTemplate } from '#/collaborative-editor/hooks/useSessionContext';
import { useWorkflowState } from '#/collaborative-editor/hooks/useWorkflow';
import { notifications } from '#/collaborative-editor/lib/notifications';
import { useURLState } from '#/react/lib/use-url-state';
import { useSession } from '#/collaborative-editor/hooks/useSession';
import { channelRequest } from '#/collaborative-editor/hooks/useChannel';
import { cn } from '#/utils/cn';
import { convertWorkflowStateToSpec } from '#/yaml/util';
import type { WorkflowState as YAMLWorkflowState } from '#/yaml/types';

// Validation schema matching backend constraints
const TemplatePublishSchema = z.object({
  name: z
    .string()
    .min(1, 'Name is required')
    .max(255, 'Name must be less than 255 characters'),
  description: z
    .string()
    .max(1000, 'Description must be less than 1000 characters')
    .optional()
    .default(''),
  tags: z.string().optional().default(''),
});

type TemplateFormValues = z.infer<typeof TemplatePublishSchema>;

export function TemplatePublishPanel() {
  const workflow = useWorkflowState(state => state.workflow);
  const jobs = useWorkflowState(state => state.jobs);
  const triggers = useWorkflowState(state => state.triggers);
  const edges = useWorkflowState(state => state.edges);
  const positions = useWorkflowState(state => state.positions);
  const workflowTemplate = useWorkflowTemplate();
  const { updateSearchParams } = useURLState();
  const { provider } = useSession();
  const channel = provider?.channel;
  const [isPublishing, setIsPublishing] = useState(false);

  // Determine if this is create or update
  const isUpdate = Boolean(workflowTemplate?.id);
  const submitButtonText = isUpdate ? 'Update Template' : 'Publish Template';

  // Default form values
  const defaultValues = useMemo<TemplateFormValues>(() => {
    if (workflowTemplate) {
      // Update mode: pre-fill with existing template data
      return {
        name: workflowTemplate.name || '',
        description: workflowTemplate.description || '',
        tags: workflowTemplate.tags?.join(', ') || '',
      };
    } else {
      // Create mode: pre-fill name with workflow name
      return {
        name: workflow?.name || '',
        description: '',
        tags: '',
      };
    }
  }, [workflow, workflowTemplate]);

  const form = useAppForm({
    defaultValues,
    validators: {
      onChange: createZodValidator(TemplatePublishSchema),
    },
  });

  const handlePublish = async () => {
    // Validate form
    const errors = form.state.errors;
    if (errors.length > 0) {
      notifications.alert({
        title: 'Validation errors',
        description: 'Please fix all errors before publishing',
      });
      return;
    }

    if (!channel || !workflow?.id) {
      notifications.alert({
        title: 'Cannot publish template',
        description: 'Channel not connected or workflow not saved',
      });
      return;
    }

    setIsPublishing(true);

    try {
      // Generate YAML code from current workflow state
      const workflowState: YAMLWorkflowState = {
        id: workflow.id,
        name: workflow.name,
        jobs: jobs as YAMLWorkflowState['jobs'],
        triggers: triggers as YAMLWorkflowState['triggers'],
        edges: edges as YAMLWorkflowState['edges'],
        positions,
      };

      const spec = convertWorkflowStateToSpec(workflowState, false);
      const workflowCode = YAML.stringify(spec);

      // Parse comma-separated tags into array
      const formValues = form.state.values as TemplateFormValues;
      const tags = formValues.tags
        .split(',')
        .map((tag: string) => tag.trim())
        .filter((tag: string) => tag.length > 0);

      // Call backend to publish/update template
      await channelRequest(channel, 'publish_template', {
        name: formValues.name,
        description: formValues.description || undefined,
        tags,
        code: workflowCode, // Send the YAML code
        positions, // Send the workflow positions
      });

      // Show success notification
      notifications.info({
        title: isUpdate ? 'Template updated' : 'Workflow published as template',
        description: isUpdate
          ? 'Your changes have been saved'
          : 'Your workflow is now available as a template',
      });

      // Navigate back to code view
      updateSearchParams({ panel: 'code' });
    } catch (error) {
      console.error('Failed to publish template:', error);
      notifications.alert({
        title: 'Failed to publish template',
        description:
          error instanceof Error
            ? error.message
            : 'An unexpected error occurred. Please try again.',
      });
    } finally {
      setIsPublishing(false);
    }
  };

  const handleCancel = () => {
    // Navigate back to code view
    updateSearchParams({ panel: 'code' });
  };

  return (
    <div className="flex flex-col h-full">
      {/* Form Content */}
      <div className="flex-1 overflow-y-auto px-4 py-5 sm:p-6">
        <div className="space-y-4 bg-white">
          <form.AppField name="name">
            {field => <field.TextField label="Name" disabled={isPublishing} />}
          </form.AppField>

          <form.AppField name="description">
            {field => (
              <field.TextAreaField
                label="Description"
                rows={6}
                disabled={isPublishing}
                placeholder="A detailed description of what this template does"
              />
            )}
          </form.AppField>

          <form.AppField name="tags">
            {field => {
              // Parse existing tags from comma-separated value
              const tagsValue = (field.state.value as string) || '';
              const existingTags = tagsValue
                .split(',')
                .map((tag: string) => tag.trim())
                .filter((tag: string) => tag.length > 0);

              // Remove a specific tag
              const handleRemoveTag = (tagToRemove: string) => {
                const updatedTags = existingTags.filter(
                  tag => tag !== tagToRemove
                );
                field.handleChange(updatedTags.join(', '));
              };

              return (
                <div>
                  <field.TextField
                    label="Tags"
                    disabled={isPublishing}
                    placeholder="Separate tags with commas (,)"
                  />
                  {existingTags.length > 0 && (
                    <div className="flex flex-wrap gap-2 mt-2">
                      {existingTags.map((tag: string, index: number) => (
                        <span
                          key={`${tag}-${index}`}
                          className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-primary-100 text-primary-700 ring-1 ring-inset ring-primary-600/20"
                        >
                          {tag}
                          <button
                            type="button"
                            onClick={() => handleRemoveTag(tag)}
                            disabled={isPublishing}
                            className="inline-flex items-center justify-center w-4 h-4 rounded-full hover:bg-primary-200 focus:outline-none focus:ring-2 focus:ring-primary-500 disabled:opacity-50 disabled:cursor-not-allowed"
                            aria-label={`Remove ${tag} tag`}
                          >
                            <span className="hero-x-mark-micro h-3 w-3" />
                          </button>
                        </span>
                      ))}
                    </div>
                  )}
                </div>
              );
            }}
          </form.AppField>
        </div>
      </div>

      {/* Footer with action buttons */}
      <div className="shrink-0 border-t border-gray-200 p-3">
        <div className="flex flex-row-reverse gap-3">
          <button
            type="button"
            onClick={handlePublish}
            disabled={isPublishing || form.state.errors.length > 0}
            className={cn(
              'rounded-md px-3 py-2 text-sm font-semibold shadow-xs',
              isPublishing || form.state.errors.length > 0
                ? 'bg-primary-300 text-white cursor-not-allowed'
                : 'bg-primary-600 text-white hover:bg-primary-700 cursor-pointer'
            )}
          >
            {isPublishing ? 'Publishing...' : submitButtonText}
          </button>
          <button
            type="button"
            onClick={handleCancel}
            disabled={isPublishing}
            className="rounded-md px-3 py-2 text-sm font-semibold bg-white hover:bg-gray-50 text-gray-900 ring-1 ring-inset ring-gray-300 shadow-xs"
          >
            Back
          </button>
        </div>
      </div>
    </div>
  );
}
