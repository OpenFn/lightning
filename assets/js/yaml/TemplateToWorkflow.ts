import type { PhoenixHook } from '../hooks/PhoenixHook';
import { parseWorkflowTemplate, convertWorkflowSpecToState } from './util';

const TemplateToWorkflow = {
  mounted() {
    this.handleEvent('template_selected', (payload: { template: string }) => {
      const workflowSpec = parseWorkflowTemplate(payload.template);
      const workflowState = convertWorkflowSpecToState(workflowSpec);
      this.pushEventTo(this.el, 'template-parsed', {
        workflow: workflowState,
      });
    });
  },
} as PhoenixHook;

export default TemplateToWorkflow;
