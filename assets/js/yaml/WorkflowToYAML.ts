import type { PhoenixHook } from '../hooks/PhoenixHook';
import type { WorkflowState } from './types';
import { convertWorkflowStateToSpec } from './util';
import YAML from 'yaml';

interface WorkflowResponse {
  workflow_params: WorkflowState;
}

const WorkflowToYAML = {
  mounted() {
    // Existing code for generating workflow code...
    this.generateWorkflowCode();

    this.handleEvent('generate_workflow_code', () => {
      this.generateWorkflowCode();
    });

    // Add: Generate YAML for AI context when component mounts
    this.generateWorkflowContext();

    // Add: Listen for AI responses
    this.handleEvent('workflow_code_generated', (payload: { code: string }) => {
      if (!payload.code) return;

      try {
        const workflowSpec = parseWorkflowYAML(payload.code);
        const workflowState = convertWorkflowSpecToState(workflowSpec);

        // Send the new state to the editor
        this.pushEvent('push-change', {
          patches: [
            {
              op: 'replace',
              path: '/',
              value: workflowState,
            },
          ],
        });
      } catch (error) {
        console.error('Failed to parse AI-generated workflow:', error);
      }
    });
  },

  generateWorkflowCode() {
    this.pushEvent('get-current-state', {}, (response: WorkflowResponse) => {
      const workflowState = response.workflow_params;

      const workflowSpec = convertWorkflowStateToSpec(workflowState);
      const yaml = YAML.stringify(workflowSpec);

      this.pushEvent('workflow_code_generated', { code: yaml });
    });
  },
  
  generateWorkflowContext() {
    this.pushEvent('get-current-state', {}, (response: WorkflowResponse) => {
      const workflowState = response.workflow_params;
      const workflowSpec = convertWorkflowStateToSpec(workflowState);

      // Remove job bodies for AI context
      Object.keys(workflowSpec.jobs).forEach(key => {
        if (workflowSpec.jobs[key].body) {
          workflowSpec.jobs[key].body = '# Existing implementation preserved';
        }
      });

      const yaml = YAML.stringify(workflowSpec);

      // Send context to the AI component
      this.pushEventTo(
        '#workflow-ai-assistant-persistent',
        'workflow_context_ready',
        {
          yaml: yaml,
        }
      );
    });
  },
} as PhoenixHook<{
  generateWorkflowCode(): void;
  generateWorkflowContext(): void;
}>;

export default WorkflowToYAML;
