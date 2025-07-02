import type { PhoenixHook } from '../hooks/PhoenixHook';
import type { WorkflowState } from './types';
import { convertWorkflowStateToSpec } from './util';
import YAML from 'yaml';

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
      
      const workflowSpec = convertWorkflowStateToSpec(workflowState);
      const yaml = YAML.stringify(workflowSpec);
      
      this.pushEvent('workflow_code_generated', { code: yaml });
    });
  },
  
  destroyed() {
    if (this.generateTimeout) {
      clearTimeout(this.generateTimeout);
    }
  }
} as PhoenixHook<{
  generateWorkflowCode(): void;
  debouncedGenerate(): void;
  generateTimeout?: ReturnType<typeof setTimeout>;  // Fix: Use ReturnType
}>;

export default WorkflowToYAML;