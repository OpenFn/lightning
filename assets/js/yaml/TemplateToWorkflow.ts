// TemplateToWorkflow.ts
import type { PhoenixHook } from '../hooks/PhoenixHook';

import { parseWorkflowTemplate, convertWorkflowSpecToState } from './util';
import {
  WorkflowError,
  formatWorkflowError,
  createWorkflowError,
} from './workflow-errors';

const TemplateToWorkflow = {
  mounted() {
    this.handleEvent('template_selected', (payload: { template: string }) => {
      try {
        const workflowSpec = parseWorkflowTemplate(payload.template);
        const workflowState = convertWorkflowSpecToState(workflowSpec);

        this.pushEventTo(this.el, 'template-parsed', {
          workflow: workflowState,
        });
      } catch (error) {
        const workflowError =
          error instanceof WorkflowError ? error : createWorkflowError(error);

        console.error('Workflow parsing error:', workflowError);

        this.pushEventTo(this.el, 'template-parse-error', {
          error: formatWorkflowError(workflowError),
          template: payload.template,
        });
      }
    });
  },
} as PhoenixHook;

export default TemplateToWorkflow;
