import YAML from 'yaml';

import type { PhoenixHook } from '../hooks/PhoenixHook';

import type { WorkflowState } from './types';
import { convertWorkflowStateToSpec } from './util';

interface WorkflowResponse {
  workflow_params: WorkflowState;
}

const WorkflowToYAML = {
  mounted() {
    this.generateWorkflowCode();

    this.handleEvent('generate_workflow_code', () => {
      this.debouncedGenerate();
    });
  },

  debouncedGenerate() {
    if (this.generateTimeout) {
      clearTimeout(this.generateTimeout);
    }

    this.generateTimeout = setTimeout(() => {
      this.generateWorkflowCode();
    }, 300);
  },

  generateWorkflowCode() {
    this.pushEvent('get-current-state', {}, (response: WorkflowResponse) => {
      const workflowState = response.workflow_params;

      const workflowSpecWithoutIds = convertWorkflowStateToSpec(
        workflowState,
        false
      );
      const workflowSpecWithIds = convertWorkflowStateToSpec(
        workflowState,
        true
      );

      const yamlWithoutIds = YAML.stringify(workflowSpecWithoutIds);
      const yamlWithIds = YAML.stringify(workflowSpecWithIds);

      this.pushEvent('workflow_code_generated', {
        code: yamlWithoutIds,
        code_with_ids: yamlWithIds,
      });
    });
  },

  destroyed() {
    if (this.generateTimeout) {
      clearTimeout(this.generateTimeout);
    }
  },
} as PhoenixHook<{
  generateWorkflowCode(): void;
  debouncedGenerate(): void;
  generateTimeout?: ReturnType<typeof setTimeout>;
}>;

export default WorkflowToYAML;
