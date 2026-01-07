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
  // pick items in the exising and check if the new matches it.

  return { hasChanges: isDiff(workflow, storeWorkflow) as boolean };
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
    return final;
  } else if (
    base &&
    target &&
    typeof base === 'object' &&
    typeof target === 'object'
  ) {
    // iterate the object and check each item
    let final = false;
    for (const key of Object.keys(base)) {
      final ||= isDiff(base[key], target[key]);
    }
    return final;
  } else {
    return target !== base;
  }
}
