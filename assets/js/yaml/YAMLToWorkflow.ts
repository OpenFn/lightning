import type { PhoenixHook } from '../hooks/PhoenixHook';

import type { WorkflowSpec, WorkflowState } from './types';
import { parseWorkflowYAML, convertWorkflowSpecToState } from './util';

function transformServerErrors(
  errors: Record<string, unknown>,
  basePath: string = ''
): string[] {
  const result: string[] = [];

  for (const [key, value] of Object.entries(errors)) {
    const currentPath = basePath ? `${basePath}/${key}` : key;

    if (Array.isArray(value)) {
      value.forEach(message => {
        result.push(`'${String(message)}' at '${currentPath}'`);
      });
    } else if (typeof value === 'object' && value !== null) {
      const nestedErrors = transformServerErrors(
        value as Record<string, unknown>,
        currentPath
      );
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

    this.viewerEl = viewerEl as HTMLTextAreaElement;
    this.fileInputEl = fileInputEl as HTMLInputElement;
    this.errorEl = errorEl;

    this.setupEventListeners();
    this.setupServerEventHandlers();
  },

  setupEventListeners() {
    this.fileInputEl.addEventListener('change', event => {
      const target = event.target as HTMLInputElement;
      const file = target.files ? target.files[0] : null;
      if (!file) return;

      const reader = new FileReader();
      reader.onload = () => {
        const fileContent = reader.result as string;
        this.viewerEl.value = fileContent;
        this.validateYAML(fileContent);
      };
      reader.readAsText(file);
    });

    this.viewerEl.addEventListener('input', event => {
      const target = event.target as HTMLTextAreaElement;
      const yamlString = target.value;
      this.validateYAML(yamlString);
    });
  },

  setupServerEventHandlers() {
    this.handleEvent('workflow-validated', () => {
      this.clearErrors();
    });

    this.handleEvent(
      'workflow-validation-errors',
      (payload: { errors: Record<string, unknown> }) => {
        const errors = transformServerErrors(payload.errors);
        this.showError(errors[0] || 'Validation failed');
      }
    );

    this.handleEvent('show-parsing-error', (payload: { error: string }) => {
      this.showError(payload.error);
    });
  },

  validateYAML(workflowYAML: string) {
    this.clearErrors();

    try {
      this.workflowSpec = parseWorkflowYAML(workflowYAML);
      this.workflowState = convertWorkflowSpecToState(this.workflowSpec);

      this.pushEventTo(this.el, 'workflow-parsed', {
        workflow: this.workflowState,
      });
    } catch (error) {
      const errorMessage = this.getErrorMessage(error);

      this.pushEventTo(this.el, 'workflow-parsing-failed', {
        error: errorMessage,
      });
    }
  },

  getErrorMessage(error: unknown): string {
    if (error instanceof Error) {
      return error.message;
    }
    if (typeof error === 'string') {
      return error;
    }
    return 'An unknown error occurred';
  },

  clearErrors() {
    this.errorEl.classList.add('hidden');
    this.errorEl.textContent = '';
    this.errorEl.classList.remove('error-shake', 'error-slide-in');
  },

  showError(message: string) {
    this.errorEl.innerHTML = `
      <span class="flex-1">${message}</span>
      <button class="text-danger-600 hover:text-danger-800 ml-2" onclick="this.closest('#workflow-errors').classList.add('hidden')">
        ✕
      </button>
    `;

    this.errorEl.classList.remove('hidden');
    this.errorEl.classList.add('error-slide-in');

    setTimeout(() => {
      this.errorEl.classList.add('error-shake');
    }, 300);

    setTimeout(() => {
      this.errorEl.classList.remove('error-shake');
    }, 800);
  },
} as PhoenixHook<{
  workflowSpec: undefined | WorkflowSpec;
  workflowState: WorkflowState;
  validateYAML: (workflowYAML: string) => void;
  updateServerState: (state: WorkflowState) => void;
  setupEventListeners: () => void;
  setupServerEventHandlers: () => void;
  getErrorMessage: (error: unknown) => string;
  clearErrors: () => void;
  showError: (message: string) => void;
  fileInputEl: HTMLInputElement;
  viewerEl: HTMLTextAreaElement;
  errorEl: HTMLElement;
}>;

export default YAMLToWorkflow;
