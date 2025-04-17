import type { PhoenixHook } from '../hooks/PhoenixHook';
import type { WorkflowSpec, WorkflowState } from './types';
import {
  parseWorkflowYAML,
  convertWorkflowSpecToState,
  defaultWorkflowState,
} from './util';

function transformServerErrors(
  errors: Record<string, any>,
  basePath: string = ''
): string[] {
  const result: string[] = [];

  for (const [key, value] of Object.entries(errors)) {
    const currentPath = basePath ? `${basePath}/${key}` : key;

    if (Array.isArray(value)) {
      // If value is an array, these are error messages
      value.forEach(message => {
        result.push(`'${message}' at '${currentPath}'`);
      });
    } else if (typeof value === 'object' && value !== null) {
      // If value is an object, recursively process it
      const nestedErrors = transformServerErrors(value, currentPath);
      result.push(...nestedErrors);
    }
  }

  return result;
}

const YAMLToWorkflow = {
  mounted() {
    const fileInputId = this.el.dataset['fileInputEl'];
    const viewerId = this.el.dataset['viewerEl'];
    const errorId = this.el.dataset['errorEl'];

    if (!viewerId || !fileInputId || !errorId) {
      throw new Error(
        'Viewer or file picker or error element data attributes are not set'
      );
    }

    const viewerEl = document.getElementById(viewerId);
    const fileInputEl = document.getElementById(fileInputId);
    const errorEl = document.getElementById(errorId);

    if (!viewerEl || !fileInputEl || !errorEl) {
      throw new Error('Viewer or file picker or error element not found');
    }

    this.viewerEl = viewerEl;
    this.fileInputEl = fileInputEl;
    this.errorEl = errorEl;

    fileInputEl.addEventListener('change', event => {
      const target = event.target as HTMLInputElement;
      const file = target.files ? target.files[0] : null;
      if (!file) return;

      const reader = new FileReader();
      reader.onload = () => {
        const fileContent = reader.result as string;
        viewerEl.value = fileContent;
        this.validateYAML(fileContent);
      };
      reader.readAsText(file);
    });

    viewerEl.addEventListener('input', event => {
      const target = event.target as HTMLTextAreaElement;
      const yamlString = target.value;

      this.validateYAML(yamlString);
    });
  },
  destroyed() {
    // reset server state
    this.updateServerState(defaultWorkflowState());
  },
  updateServerState(state: WorkflowState) {
    this.pushEvent('validate', { workflow: state });
  },
  validateYAML(workflowYAML: string) {
    this.errorEl.classList.add('hidden');
    this.errorEl.textContent = '';
    try {
      this.workflowSpec = parseWorkflowYAML(workflowYAML);
      this.workflowState = convertWorkflowSpecToState(this.workflowSpec);

      this.pushEventTo(
        this.el,
        'validate-parsed-workflow',
        { workflow: this.workflowState },
        response => {
          if (response['errors']) {
            // these are based on those sent by the provisioner API. ideally, we should have the provisioner return the id of the affected node
            // then we can map them to the YAML path here. At this point we have both the Spec and State
            const errors = transformServerErrors(response['errors']);
            this.errorEl.textContent = errors[0];
            this.errorEl.classList.remove('hidden');
          } else {
            this.updateServerState(this.workflowState);
          }
        }
      );
    } catch (error) {
      this.errorEl.textContent = error.message;
      this.errorEl.classList.remove('hidden');

      // dummy invalidate the server parsed worklow
      this.pushEventTo(this.el, 'validate-parsed-workflow', { workflow: {} });
    }
  },
} as PhoenixHook<{
  workflowSpec: undefined | WorkflowSpec;
  workflowState: WorkflowState;
  validateYAML: (workflowYAML: string) => void;
  updateServerState: (state: WorkflowState) => void;
  fileInputEl: HTMLElement;
  viewerEl: HTMLElement;
  errorEl: HTMLElement;
}>;

export default YAMLToWorkflow;
