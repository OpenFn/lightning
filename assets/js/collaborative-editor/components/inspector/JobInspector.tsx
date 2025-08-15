import { useForm } from "@tanstack/react-form";
import type React from "react";
import { useWorkflowActions } from "#/collaborative-editor/hooks/Workflow";
import { JobSchema } from "#/collaborative-editor/types/job";
import type { Workflow } from "#/collaborative-editor/types/workflow";

interface JobInspectorProps {
  job: Workflow.Job;
}

/**
 * Creates a TanStack Form validator function using a Zod schema.
 * This approach provides full Zod validation while maintaining TanStack Form compatibility.
 *
 * @param schema - Zod schema to use for validation
 * @returns TanStack Form compatible validator function
 */
const createZodValidator = <T,>(schema: any) => {
  return ({ value }: { value: T }) => {
    const result = schema.safeParse(value);
    if (!result.success) {
      // Convert Zod errors to TanStack Form format
      const formErrors: Record<string, string> = {};
      result.error.issues.forEach((issue: any) => {
        const path = issue.path.join(".");
        formErrors[path] = issue.message;
      });
      return { fields: formErrors };
    }
    return undefined;
  };
};

export const JobInspector: React.FC<JobInspectorProps> = ({ job }) => {
  const { updateJob } = useWorkflowActions();

  const form = useForm({
    defaultValues: {
      id: job.id || "",
      name: job.name || "",
      body: job.body || "",
      adaptor: job.adaptor || "@openfn/language-common@latest",
      project_credential_id: job.project_credential_id || undefined,
      keychain_credential_id: job.keychain_credential_id || undefined,
      workflow_id: job.workflow_id || undefined,
      delete: job.delete || false,
      inserted_at: job.inserted_at || undefined,
      updated_at: job.updated_at || undefined,
      enabled: job.enabled ?? true,
    },
    listeners: {
      onChange: ({ formApi }) => {
        if (job.id) {
          updateJob(job.id, formApi.state.values);
        }
      },
    },
    validators: {
      onChange: createZodValidator(JobSchema),
    },
  });

  return (
    <div className="">
      <div className="-mt-6 md:grid md:grid-cols-6 md:gap-4 p-2 @container">
        <div className="col-span-6">
          <form.Field name="name">
            {(field) => (
              <div>
                <label
                  htmlFor={field.name}
                  className="text-xs text-gray-500 mb-1 block"
                >
                  Name
                </label>
                <input
                  type="text"
                  id={field.name}
                  value={field.state.value}
                  onChange={(e) => field.handleChange(e.target.value)}
                  className="focus:outline focus:outline-2 focus:outline-offset-1 block w-full rounded-lg text-slate-900 focus:ring-0 sm:text-sm sm:leading-6 phx-no-feedback:border-slate-300 phx-no-feedback:focus:border-slate-400 disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500 border-slate-300 focus:border-slate-400 focus:outline-indigo-600"
                />
                {field.state.meta.errors?.map((error, i) => {
                  const errorMessage =
                    typeof error === "string"
                      ? error
                      : (error as any)?.message || "Invalid input";
                  return (
                    <p
                      key={`error-${field.name}-${i}`}
                      data-tag="error_message"
                      className="mt-1 inline-flex items-center gap-x-1.5 text-xs text-danger-600"
                    >
                      <span className="hero-exclamation-circle size-4"></span>
                      {errorMessage}
                    </p>
                  );
                }) || null}
              </div>
            )}
          </form.Field>
        </div>
      </div>
      <div className="col-span-6">
        <label htmlFor="body" className="text-xs text-gray-500 mb-1 block">
          Body Preview
        </label>
        <div className="bg-gray-50 p-2 rounded text-xs font-mono max-h-32 overflow-y-auto">
          <pre className="whitespace-pre-wrap text-gray-700">
            {job.body || "// No code yet"}
          </pre>
        </div>
      </div>
    </div>
  );
};
