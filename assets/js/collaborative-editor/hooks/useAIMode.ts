import { useMemo } from 'react';

import { useURLState } from '../../react/lib/use-url-state';
import type {
  SessionType,
  JobCodeContext,
  WorkflowTemplateContext,
} from '../types/ai-assistant';

import { useProject } from './useSessionContext';
import { useWorkflowState } from './useWorkflow';

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
  const { params } = useURLState();
  const project = useProject();
  const workflow = useWorkflowState(state => state.workflow);
  const jobs = useWorkflowState(state => state.jobs);

  return useMemo(() => {
    if (!project) {
      return null;
    }

    const isIDEOpen = params.panel === 'editor';
    const selectedJobId = params.job;

    let jobCtx: JobCodeContext | undefined;
    if (isIDEOpen && selectedJobId) {
      const job = jobs.find(j => j.id === selectedJobId);

      jobCtx = {
        job_id: selectedJobId,
        attach_code: false,
        attach_logs: false,
      };

      if (workflow?.id) {
        jobCtx.workflow_id = workflow.id;
      }

      if (job) {
        jobCtx.job_name = job.name;
        jobCtx.job_body = job.body;
        jobCtx.job_adaptor = job.adaptor;
      }

      const runId = params.run;
      if (runId) {
        jobCtx.follow_run_id = runId;
      }
    }

    return {
      mode: 'workflow_template',
      context: {
        project_id: project.id,
        ...(workflow?.id && { workflow_id: workflow.id }),
        jobCtx,
      },
      storageKey: workflow?.id
        ? `ai-workflow-${workflow.id}`
        : `ai-project-${project.id}`,
    };
  }, [params, project, workflow, jobs]);
}
