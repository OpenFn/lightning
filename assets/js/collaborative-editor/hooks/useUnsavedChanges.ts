import { useSessionContext } from './useSessionContext';
import { useWorkflowState } from './useWorkflow';

export function useUnsavedChanges() {
  const { workflow } = useSessionContext();
  const wf = {
    jobs: workflow?.jobs.map(j => ({
      id: j.id,
      name: j.name,
      body: j.body || '',
      adaptor: j.adaptor,
      project_credential_id: j.project_credential_id,
      keychain_credential_id: j.keychain_credential_id,
    })),
    triggers: workflow?.triggers.map(t => ({
      cron_expression: t.cron_expression,
      enabled: t.enabled,
      id: t.id,
      type: t.type,
    })),
    edges: workflow?.edges.map(e => ({
      condition_expression: e.condition_expression,
      condition_label: e.condition_label,
      condition_type: e.condition_type,
      enabled: e.enabled,
      id: e.id,
      source_job_id: e.source_job_id,
      source_trigger_id: e.source_trigger_id,
      target_job_id: e.target_job_id,
    })),
    positions: workflow?.positions || {},
    name: workflow?.name,
  };
  const storeWorkflow = useWorkflowState(state => ({
    jobs: state.jobs.map(j => ({
      id: j.id,
      name: j.name,
      body: j.body || '',
      adaptor: j.adaptor,
      project_credential_id: j.project_credential_id,
      keychain_credential_id: j.keychain_credential_id,
    })),
    triggers: state.triggers.map(t => ({
      cron_expression: t.cron_expression,
      enabled: t.enabled,
      id: t.id,
      type: t.type,
    })),
    edges: state.edges.map(e => ({
      condition_expression: e.condition_expression,
      condition_label: e.condition_label,
      condition_type: e.condition_type,
      enabled: e.enabled,
      id: e.id,
      source_job_id: e.source_job_id,
      source_trigger_id: e.source_trigger_id,
      target_job_id: e.target_job_id,
    })),
    positions: state.positions || {},
    name: state.workflow?.name,
  }));

  // pick items in the exising and check if the new matches it.

  return { hasChanges: isDiff(wf, storeWorkflow) };
}

function isDiff(base: unknown, target: unknown) {
  const undef = [undefined, null, ''];
  // @ts-expect-error
  if (undef.includes(base) && undef.includes(target)) return false;
  if (typeof base !== typeof target) return true;
  if (Array.isArray(base) && Array.isArray(target)) {
    if (base.length !== target.length) return true;
    // enter the array
    // iterate the array and check each item
    let final = false;
    for (let idx = 0; idx < base.length; idx++) {
      final ||= isDiff(base[idx], target[idx]);
    }
    console.log('array:final', final);
    return final;
  } else if (
    base &&
    target &&
    typeof base === 'object' &&
    typeof target === 'object'
  ) {
    // iterate the object and check each item
    let final = false;
    console.log(':final', Object.keys(base));
    for (const key of Object.keys(base)) {
      final ||= isDiff(base[key], target[key]);
    }
    console.log('object:final', final);
    return final;
  } else {
    return target !== base;
  }
}
