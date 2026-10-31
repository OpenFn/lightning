import type { PhoenixHook } from '../hooks/PhoenixHook';

import { serializeWorkflow } from './format';
import type { WorkflowState } from './types';

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

      // v2 (CLI-aligned portability format) is stateless — no UUIDs in the
      // canonical body. Both `code` and `code_with_ids` payloads carry the
      // same v2 string after #4718's export cutover.
      const yamlCode = serializeWorkflow(workflowState);

      this.pushEvent('workflow_code_generated', {
        code: yamlCode,
        code_with_ids: yamlCode,
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
