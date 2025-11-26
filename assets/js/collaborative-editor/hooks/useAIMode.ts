import { useMemo } from 'react';

import { useURLState } from '../../react/lib/use-url-state';
import { useProject } from './useSessionContext';
import { useWorkflowState } from './useWorkflow';

import type {
  SessionType,
  JobCodeContext,
  WorkflowTemplateContext,
} from '../types/ai-assistant';

export interface AIModeResult {
  mode: SessionType;
  context: JobCodeContext | WorkflowTemplateContext;
  storageKey: string;
}

/**
 * Hook to determine the current AI Assistant mode based on UI state
 *
 * Returns the appropriate mode and context:
 * - job_code: When IDE is open for a specific job
 * - workflow_template: When viewing the workflow diagram (default)
 *
 * The mode determines:
 * - Which AI service endpoint to use
 * - What context to send to the AI
 * - Which session to load from storage
 */
export function useAIMode(): AIModeResult | null {
  const { searchParams } = useURLState();
  const project = useProject();
  const workflow = useWorkflowState(state => state.workflow);
  const jobs = useWorkflowState(state => state.jobs);

  return useMemo(() => {
    if (!project) return null;

    // Check if IDE is open for a specific job
    const isIDEOpen = searchParams.get('panel') === 'editor';
    const selectedJobId = searchParams.get('job');

    if (isIDEOpen && selectedJobId) {
      // Find job data from Y.Doc
      const job = jobs.find(j => j.id === selectedJobId);

      // Job Code Mode - editing a specific job
      const context: JobCodeContext = {
        job_id: selectedJobId,
        attach_code: false,
        attach_logs: false,
      };

      // Always include workflow_id if available (even for unsaved jobs)
      if (workflow?.id) {
        context.workflow_id = workflow.id;
      }

      // If job exists in Y.Doc, include its data for unsaved job support
      if (job) {
        context.job_name = job.name;
        context.job_body = job.body;
        context.job_adaptor = job.adaptor;
      }

      // Include follow_run_id if run parameter is present in URL
      const runId = searchParams.get('run');
      if (runId) {
        context.follow_run_id = runId;
      }

      return {
        mode: 'job_code',
        context,
        storageKey: `ai-job-${selectedJobId}`,
      };
    }

    // Workflow Template Mode - viewing workflow diagram (default)
    return {
      mode: 'workflow_template',
      context: {
        project_id: project.id,
        ...(workflow?.id && { workflow_id: workflow.id }),
      },
      storageKey: workflow?.id
        ? `ai-workflow-${workflow.id}`
        : `ai-project-${project.id}`,
    };
  }, [searchParams, project, workflow, jobs]);
}
