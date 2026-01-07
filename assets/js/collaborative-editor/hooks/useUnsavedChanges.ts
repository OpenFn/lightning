import type { Workflow } from '../types/workflow';

import { useSessionContext } from './useSessionContext';
import { useWorkflowState } from './useWorkflow';

export function useUnsavedChanges() {
  const { workflow } = useSessionContext();
  const storeWorkflow = useWorkflowState(state => ({
    jobs: state.jobs,
    triggers: state.triggers,
    edges: state.edges,
    positions: state.positions || {},
    name: state.workflow?.name,
  }));
  if (!workflow || !storeWorkflow)
    return {
      hasChanges: false,
    };
  return {
    hasChanges: isDiffWorkflow(
      transformWorkflow(workflow || {}),
      transformWorkflow((storeWorkflow as Workflow) || {})
    ),
  };
}

// we need the same structure of workflows to be able to compare
function transformWorkflow(workflow: Workflow) {
  return {
    name: workflow.name,
    jobs: (workflow.jobs || [])
      .map(job => ({
        id: job.id,
        name: job.name,
        body: job.body,
        adaptor: job.adaptor,
        project_credential_id: job.project_credential_id,
        keychain_credential_id: job.keychain_credential_id,
      }))
      .sort((a, b) => a.id.localeCompare(b.id)),
    edges: (workflow.edges || [])
      .map(edge => ({
        id: edge.id,
        source_job_id: edge.source_job_id,
        source_trigger_id: edge.source_trigger_id,
        target_job_id: edge.target_job_id,
        enabled: edge.enabled || false,
        condition_type: edge.condition_type,
        condition_label: edge.condition_label,
        condition_expression: edge.condition_expression,
      }))
      .sort((a, b) => a.id.localeCompare(b.id)),
    trigger: (workflow.triggers || []).map(trigger => ({
      id: trigger.id,
      type: trigger.type,
      enabled: trigger.enabled,
      cron_expression: trigger.cron_expression,
    })),
    positions: workflow.positions || {},
  };
}

function isDiffWorkflow(base: unknown, target: unknown): boolean {
  const undef = [undefined, null, ''];
  // @ts-expect-error
  if (undef.includes(base) && undef.includes(target)) return false;
  if (typeof base !== typeof target) return true;
  if (Array.isArray(base) && Array.isArray(target)) {
    if (base.length !== target.length) return true;
    return base.some((v, i) => isDiffWorkflow(v, target[i]));
  } else if (
    base &&
    target &&
    typeof base === 'object' &&
    typeof target === 'object'
  ) {
    return Object.keys(base).some(k => isDiffWorkflow(base[k], target[k]));
  } else {
    return target !== base;
  }
}
