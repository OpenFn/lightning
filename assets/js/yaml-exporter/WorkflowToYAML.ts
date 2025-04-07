import type { PhoenixHook } from '../hooks/PhoenixHook';
import type { WorkflowState } from './types';
import { convertWorkflowStateToSpec } from './util';
import YAML from 'yaml';

const WorkflowToYAML = {
  mounted() {
    this.getState();
  },
  updated() {
    this.getState();
  },
  getState() {
    const viewerId = this.el.dataset.viewerEl;
    const loadingId = this.el.dataset.loadingEl;

    if (!viewerId || !loadingId) {
      throw new Error('Viewer or loading element data attributes are not set');
    }

    const viewerEl = document.getElementById(viewerId);
    const loadingEl = document.getElementById(loadingId);

    if (!viewerEl || !loadingEl) {
      throw new Error('Viewer or loading element not found');
    }

    this.pushEvent('get-current-state', {}, response => {
      const workflowState = response['workflow_params'] as WorkflowState;

      const workflowSpec = convertWorkflowStateToSpec(workflowState);
      const result = YAML.stringify(workflowSpec);

      viewerEl.classList.remove('hidden');
      loadingEl.classList.add('hidden');

      viewerEl.value = result;

      this.workflowState = workflowState;
    });
  },
} as PhoenixHook<{
  getState: () => void;
  workflowState: undefined | WorkflowState;
}>;

export default WorkflowToYAML;
