import { useMemo, useState } from 'react';

import { useAppForm } from '#/collaborative-editor/components/form';
import { createZodValidator } from '#/collaborative-editor/components/form/createZodValidator';
import {
  usePermissions,
  useProject,
} from '#/collaborative-editor/hooks/useSessionContext';
import {
  useWorkflowActions,
  useWorkflowReadOnly,
  useWorkflowState,
} from '#/collaborative-editor/hooks/useWorkflow';
import { notifications } from '#/collaborative-editor/lib/notifications';
import { createWorkflowSchema } from '#/collaborative-editor/types/workflow';
import { useURLState } from '#/react/lib/use-url-state';

import { AlertDialog } from '../AlertDialog';

export function WorkflowSettings() {
  // Get workflow from store - LoadingBoundary guarantees it's non-null
  const workflow = useWorkflowState(state => state.workflow);
  const [isResetDialogOpen, setIsResetDialogOpen] = useState(false);
  const [isResetting, setIsResetting] = useState(false);

  const { updateWorkflow, resetWorkflow } = useWorkflowActions();
  const { isReadOnly } = useWorkflowReadOnly();
  const permissions = usePermissions();
  const project = useProject();

  const { updateSearchParams } = useURLState();

  const projectConcurrency = project?.concurrency ?? null;

  // Check if project has concurrency disabled (concurrency === 1)
  const isProjectConcurrencyDisabled = projectConcurrency === 1;

  const handleViewAsYAML = () => {
    updateSearchParams({ panel: 'code' });
  };

  // LoadingBoundary guarantees workflow is non-null at this point
  if (!workflow) {
    throw new Error('Workflow must be loaded');
  }

  const defaultValues = useMemo(() => {
    // Y.Doc types can be loosely typed, so we assert to expected types
    const concurrency = workflow.concurrency ?? null;
    const enableJobLogs = workflow.enable_job_logs ?? false;

    return {
      id: workflow.id,
      name: workflow.name,
      lock_version: workflow.lock_version,
      deleted_at: workflow.deleted_at,
      concurrency,
      enable_job_logs: enableJobLogs,
    };
  }, [workflow]);

  const form = useAppForm({
    defaultValues,
    listeners: {
      onChange: ({ formApi }) => {
        // Form → Y.Doc: Update workflow immediately on change
        const { name, concurrency, enable_job_logs } = formApi.state
          .values as typeof defaultValues;
        updateWorkflow({
          name,
          concurrency,
          enable_job_logs,
        });
      },
    },
    validators: {
      onChange: createZodValidator(createWorkflowSchema(projectConcurrency)),
    },
  });

<<<<<<< HEAD
=======
  // Yjs → Form: Watch for external changes
  useWatchFields(
    workflow,
    changedFields => {
      const values = form.state.values as typeof defaultValues;
      Object.entries(changedFields).forEach(([key, value]) => {
        if (key in values) {
          const fieldName = key as keyof typeof defaultValues;
          form.setFieldValue(fieldName, value);
          // Revalidate if field previously had errors (fixes Ctrl+Z clearing)
          void form.validateField(fieldName, 'change');
        }
      });
    },
    ['name', 'concurrency', 'enable_job_logs']
  );

>>>>>>> 43cfaa977b (feat: Add project concurrency validation to workflow settings)
  const handleReset = async () => {
    setIsResetting(true);
    try {
      await resetWorkflow();
      // Success - dialog will close, user sees changes via Y.Doc sync
    } catch (error) {
      // Show error notification to user
      notifications.alert({
        title: 'Failed to reset workflow',
        description:
          error instanceof Error
            ? error.message
            : 'An unexpected error occurred. Please try again.',
      });
    } finally {
      setIsResetting(false);
      setIsResetDialogOpen(false);
    }
  };

  return (
    <div className="px-6 py-6 space-y-4">
      {/* Workflow Name Field */}
      <form.AppField name="name">
        {field => (
          <field.TextField label="Workflow Name" disabled={isReadOnly} />
        )}
      </form.AppField>

      {/* YAML View Section - Placeholder (NOT implementing) */}
      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-2">
          Workflow as YAML
        </h3>
        <button
          type="button"
          onClick={handleViewAsYAML}
          className="text-sm text-indigo-600 hover:text-indigo-500"
          id="view-workflow-as-yaml-link"
        >
          View your workflow as YAML code
        </button>
      </div>

      {/* Log Output Toggle */}
      <form.AppField name="enable_job_logs">
        {field => (
          <field.ToggleField
            label="Allow console.log() usage"
            description="Control what's printed in run logs"
            disabled={isReadOnly}
          />
        )}
      </form.AppField>

      {/* Concurrency Section */}
      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-2">Concurrency</h3>
        <p className="text-sm text-gray-600 mb-3">
          Control how many of this workflow's <em>Runs</em> are executed at the
          same time
        </p>
        <form.AppField name="concurrency">
          {field => (
            <>
              <field.NumberField
                label="Max Concurrency"
                placeholder="Unlimited (up to max available)"
                helpText={
                  field.state.value === null
                    ? 'Unlimited (up to max available)'
                    : undefined
                }
                min={1}
                max={projectConcurrency ?? undefined}
                disabled={isReadOnly || isProjectConcurrencyDisabled}
              />
              {isProjectConcurrencyDisabled && (
                <div className="text-xs mt-2">
                  <div className="italic text-gray-500">
                    Parallel execution of runs is disabled for this project.
                    This setting will have no effect. You can modify your
                    Project Concurrency setting on the{' '}
                    <a
                      href={`/projects/${project?.id}/settings`}
                      className="text-indigo-600 hover:text-indigo-500 underline"
                    >
                      project setup
                    </a>{' '}
                    page.
                  </div>
                </div>
              )}
            </>
          )}
        </form.AppField>
      </div>

      {/* Reset Section - Only show if user has edit permission */}
      {permissions?.can_edit_workflow && !isReadOnly && (
        <div className="border-t border-gray-200 pt-6">
          <h3 className="text-sm font-medium text-gray-900 mb-2">
            Reset Workflow
          </h3>
          <p className="text-sm text-gray-600 mb-4">
            Discard all uncommitted changes and restore the workflow to its
            latest saved snapshot. This action cannot be undone.
          </p>
          <button
            type="button"
            onClick={() => setIsResetDialogOpen(true)}
            disabled={isResetting}
            className="rounded-md bg-red-600 px-3 py-2 text-sm
            font-semibold text-white shadow-xs hover:bg-red-500
            focus-visible:outline-2 focus-visible:outline-offset-2
            focus-visible:outline-red-600
            disabled:bg-red-300 disabled:hover:bg-red-300
            disabled:cursor-not-allowed"
          >
            {isResetting ? 'Resetting...' : 'Reset to Latest Snapshot'}
          </button>
        </div>
      )}

      <AlertDialog
        isOpen={isResetDialogOpen}
        onClose={() => !isResetting && setIsResetDialogOpen(false)}
        onConfirm={() => {
          void handleReset();
        }}
        title="Reset Workflow?"
        description="This will undo all uncommitted changes and restore
          the workflow to its latest snapshot. This action cannot
          be undone."
        confirmLabel={isResetting ? 'Resetting...' : 'Reset Workflow'}
        cancelLabel="Cancel"
        variant="danger"
      />
    </div>
  );
}
