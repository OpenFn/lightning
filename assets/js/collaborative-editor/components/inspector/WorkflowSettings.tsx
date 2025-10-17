import { useEffect, useMemo, useState } from "react";

import { useAppForm } from "#/collaborative-editor/components/form";
import { createZodValidator } from "#/collaborative-editor/components/form/createZodValidator";
import { usePermissions } from "#/collaborative-editor/hooks/useSessionContext";
import { useWorkflowActions } from "#/collaborative-editor/hooks/useWorkflow";
import { useWatchFields } from "#/collaborative-editor/stores/common";
import type { Workflow } from "#/collaborative-editor/types/workflow";
import { WorkflowSchema } from "#/collaborative-editor/types/workflow";

import { AlertDialog } from "../AlertDialog";

interface WorkflowSettingsProps {
  workflow: Workflow;
}

export function WorkflowSettings({ workflow }: WorkflowSettingsProps) {
  const [isResetDialogOpen, setIsResetDialogOpen] = useState(false);
  const [isResetting, setIsResetting] = useState(false);

  const { updateWorkflow, resetWorkflow } = useWorkflowActions();
  const permissions = usePermissions();

  const defaultValues = useMemo(
    () => ({
      id: workflow.id,
      name: workflow.name,
      lock_version: workflow.lock_version,
      deleted_at: workflow.deleted_at,
      // Virtual fields for future use (not yet in Y.Doc)
      concurrency: null as number | null,
      enable_job_logs: true,
    }),
    [workflow]
  );

  const form = useAppForm({
    defaultValues,
    listeners: {
      onChange: ({ formApi }) => {
        // Form → Y.Doc: Update workflow immediately on change
        const { name } = formApi.state.values;
        updateWorkflow({
          name,
          // Note: concurrency and enable_job_logs will be no-ops
          // until Y.Doc type is updated
        });
      },
    },
    validators: {
      onChange: createZodValidator(WorkflowSchema),
    },
  });

  // Yjs → Form: Watch for external changes
  useWatchFields(
    workflow,
    changedFields => {
      Object.entries(changedFields).forEach(([key, value]) => {
        if (key in form.state.values) {
          form.setFieldValue(key as keyof typeof form.state.values, value);
        }
      });
    },
    ["name"]
  );

  // Reset form when workflow changes
  useEffect(() => {
    form.reset();
  }, [workflow.id, form]);

  const handleReset = async () => {
    setIsResetting(true);
    try {
      await resetWorkflow();
      // Success - dialog will close, user sees changes via Y.Doc sync
    } catch (error) {
      // Error - just log for now (no notification system exists)
      console.error("Reset failed:", error);
    } finally {
      setIsResetting(false);
      setIsResetDialogOpen(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Workflow Name Field */}
      <div>
        <form.AppField name="name">
          {field => <field.TextField label="Workflow Name" />}
        </form.AppField>
      </div>

      {/* YAML View Section - Placeholder (NOT implementing) */}
      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-2">
          Workflow as YAML
        </h3>
        <button
          type="button"
          className="text-sm text-indigo-600 hover:text-indigo-500"
        >
          View your workflow as YAML code
        </button>
      </div>

      {/* Log Output Toggle */}
      <div>
        <form.AppField name="enable_job_logs">
          {field => (
            <field.ToggleField
              label="Allow console.log() usage"
              description="Control what's printed in run logs"
            />
          )}
        </form.AppField>
      </div>

      {/* Concurrency Section */}
      <div>
        <h3 className="text-sm font-medium text-gray-900 mb-2">Concurrency</h3>
        <p className="text-sm text-gray-600 mb-3">
          Control how many of this workflow's <em>Runs</em> are executed at the
          same time
        </p>
        <form.AppField name="concurrency">
          {field => (
            <field.NumberField
              label="Max Concurrency"
              placeholder="Unlimited (up to max available)"
              helpText={
                field.state.value === null
                  ? "Unlimited (up to max available)"
                  : undefined
              }
              min={1}
            />
          )}
        </form.AppField>
      </div>

      {/* Reset Section - Only show if user has edit permission */}
      {permissions?.can_edit_workflow && (
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
            disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isResetting ? "Resetting..." : "Reset to Latest Snapshot"}
          </button>
        </div>
      )}

      <AlertDialog
        isOpen={isResetDialogOpen}
        onClose={() => !isResetting && setIsResetDialogOpen(false)}
        onConfirm={handleReset}
        title="Reset Workflow?"
        description="This will undo all uncommitted changes and restore
          the workflow to its latest snapshot. This action cannot
          be undone."
        confirmLabel={isResetting ? "Resetting..." : "Reset Workflow"}
        cancelLabel="Cancel"
        variant="danger"
      />
    </div>
  );
}
