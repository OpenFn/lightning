import type { Trigger } from '../types/trigger';
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

  if (!workflow || !storeWorkflow) return { hasChanges: false };
  return {
    hasChanges: isDiffWorkflow(
      transformWorkflow(workflow),
      transformWorkflow(storeWorkflow as Workflow)
    ),
  };
}

// transform workflow to normalized structure for comparison
function transformWorkflow(workflow: Workflow) {
  return {
    name: workflow.name,
    jobs: (workflow.jobs || [])
      .map(job => ({
        id: job.id,
        name: job.name.trim(),
        body: job.body.trim(),
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
        condition_label: edge.condition_label?.trim(),
        condition_expression: edge.condition_expression?.trim(),
      }))
      .sort((a, b) => a.id.localeCompare(b.id)),
    triggers: (workflow.triggers || []).map(trigger =>
      transformTrigger(trigger)
    ),
    positions: workflow.positions || {},
  };
}

function transformTrigger(trigger: Trigger) {
  const output: Partial<Trigger> = {
    id: trigger.id,
    type: trigger.type,
    enabled: trigger.enabled,
  };
  switch (trigger.type) {
    case 'cron':
      output.cron_expression = trigger.cron_expression;
      break;
    case 'kafka':
      output.kafka_configuration = trigger.kafka_configuration;
      break;
    case 'webhook':
      break;
  }
  return output;
}

// deep comparison to detect workflow changes
function isDiffWorkflow(base: unknown, target: unknown): boolean {
  const isNullish = (v: unknown) => v === undefined || v === null || v === '';
  if (isNullish(base) && isNullish(target)) return false;
  if (typeof base !== typeof target) return true;

  if (Array.isArray(base) && Array.isArray(target)) {
    return (
      base.length !== target.length ||
      base.some((v, i) => isDiffWorkflow(v, target[i]))
    );
  }

  if (
    base &&
    target &&
    typeof base === 'object' &&
    typeof target === 'object'
  ) {
    const baseObj = base as Record<string, unknown>;
    const targetObj = target as Record<string, unknown>;
    const keys = [
      ...new Set(Object.keys(baseObj).concat(Object.keys(targetObj))),
    ];
    return keys.some(k => isDiffWorkflow(baseObj[k], targetObj[k]));
  }

  return base !== target;
}
