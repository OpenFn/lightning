import type { PhoenixHook } from '../hooks/PhoenixHook';
import type { WorkflowSpec } from './types';
// import { convertWorkflowStateToSpec } from './util';
import workflowV1Schema from './schema/workflow-v1';
import YAML from 'yaml';
import Ajv from 'ajv';

const ajv = new Ajv({ allErrors: true });
const validate = ajv.compile(workflowV1Schema);

function validateYAML(yamlString: string) {
  try {
    // Parse YAML to JavaScript object
    const data = YAML.parse(yamlString);

    // Validate against schema
    const valid = validate(data);

    if (!valid) {
      return {
        valid: false,
        errors: validate.errors,
      };
    }

    return {
      valid: true,
      data: data as WorkflowSpec,
    };
  } catch (error) {
    return {
      valid: false,
      errors: [{ message: `YAML parsing error: ${error.message}` }],
    };
  }
}

const YAMLToWorkflow = {
  mounted() {
    const fileInputId = this.el.dataset.fileInputEl;
    const viewerId = this.el.dataset.viewerEl;
    const errorId = this.el.dataset.errorEl;

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

    fileInputEl.addEventListener('change', event => {
      const target = event.target as HTMLInputElement;
      const file = target.files ? target.files[0] : null;
      if (!file) return;

      const reader = new FileReader();
      reader.onload = () => {
        const fileContent = reader.result as string;

        viewerEl.value = fileContent;
        const result = validateYAML(fileContent);
        console.log(result);
      };
      reader.readAsText(file);
    });

    viewerEl.addEventListener('input', event => {
      const target = event.target as HTMLTextAreaElement;
      const yamlString = target.value;

      const result = validateYAML(yamlString);

      if (!result.valid) {
        console.log('errors', result.errors);
        errorEl.textContent = result.errors
          .map(error => error.message)
          .join('\n');
        errorEl.classList.remove('hidden');
      } else {
        console.log(result.data);
      }
    });
  },
} as PhoenixHook<{
  workflowSpec: undefined | WorkflowSpec;
}>;

export default YAMLToWorkflow;
