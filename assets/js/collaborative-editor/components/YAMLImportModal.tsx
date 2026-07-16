import { Dialog, DialogBackdrop, DialogPanel } from '@headlessui/react';
import pDebounce from 'p-debounce';
import { useState, useCallback, useEffect, useRef } from 'react';

import { Tooltip } from '../../components/Tooltip';
import type { WorkflowState as YAMLWorkflowState } from '../../yaml/types';
import { parseWorkflowYAML, convertWorkflowSpecToState } from '../../yaml/util';
import { WorkflowError } from '../../yaml/workflow-errors';
import {
  useImportPanelState,
  useImportYamlContent,
  useShowYAMLImportModal,
  useUICommands,
} from '../hooks/useUI';
import { useCreateWorkflowFlow } from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';

import { ValidationErrorDisplay } from './yaml-import/ValidationErrorDisplay';
import { YAMLCodeEditor } from './yaml-import/YAMLCodeEditor';
import { YAMLFileDropzone } from './yaml-import/YAMLFileDropzone';

export function YAMLImportModal() {
  const isOpen = useShowYAMLImportModal();
  const { closeYAMLImportModal, dismissLandingScreen } = useUICommands();

  useKeyboardShortcut('Escape', closeYAMLImportModal, 100, { enabled: isOpen });

  return (
    <Dialog
      open={isOpen}
      onClose={closeYAMLImportModal}
      className="relative z-20"
      aria-label="Import a workflow"
    >
      <DialogBackdrop
        transition
        className="modal-backdrop data-closed:opacity-0 data-enter:duration-300
          data-enter:ease-out data-leave:duration-200 data-leave:ease-in"
      />

      <div className="fixed inset-0 z-10 flex items-center justify-center p-4">
        <DialogPanel
          transition
          className="bg-white rounded-2xl shadow-2xl w-full max-w-lg flex flex-col
            data-closed:opacity-0 data-closed:scale-95
            data-enter:duration-300 data-enter:ease-out
            data-leave:duration-200 data-leave:ease-in"
        >
          <YAMLImportContent
            onClose={closeYAMLImportModal}
            onSuccess={dismissLandingScreen}
          />
        </DialogPanel>
      </div>
    </Dialog>
  );
}

interface YAMLImportContentProps {
  onClose: () => void;
  onSuccess: () => void;
}

function YAMLImportContent({ onClose, onSuccess }: YAMLImportContentProps) {
  const { createWorkflowFrom } = useCreateWorkflowFlow();
  const { setImportState, setImportYamlContent } = useUICommands();

  const storedYamlContent = useImportYamlContent();
  const importState = useImportPanelState();

  const [yamlContent, setYamlContent] = useState(storedYamlContent);
  const [errors, setErrors] = useState<WorkflowError[]>([]);
  const [validatedState, setValidatedState] =
    useState<YAMLWorkflowState | null>(null);
  const [mode, setMode] = useState<'upload' | 'paste'>('upload');

  const debouncedValidate = useRef(
    pDebounce((content: string) => {
      if (!content.trim()) {
        setImportState('initial');
        setErrors([]);
        setValidatedState(null);
        return;
      }

      setImportState('parsing');
      try {
        const spec = parseWorkflowYAML(content);
        const state = convertWorkflowSpecToState(spec);
        setValidatedState(state);
        setImportState('valid');
        setErrors([]);
      } catch (error) {
        if (error instanceof WorkflowError) {
          setErrors([error]);
        } else {
          console.error('Unexpected validation error:', error);
          setErrors([]);
        }
        setImportState('invalid');
        setValidatedState(null);
      }
    }, 300)
  );

  const validateYAML = useCallback((content: string) => {
    void debouncedValidate.current(content);
  }, []);

  const handleYAMLChange = (content: string) => {
    setYamlContent(content);
    setImportYamlContent(content);
    void validateYAML(content);
  };

  const handleFileUpload = (content: string) => {
    setMode('paste');
    setYamlContent(content);
    setImportYamlContent(content);
    void validateYAML(content);
  };

  const hasRestoredRef = useRef(false);
  useEffect(() => {
    if (hasRestoredRef.current) return;
    hasRestoredRef.current = true;

    if (storedYamlContent) {
      void validateYAML(storedYamlContent);
    }
  }, [storedYamlContent, validateYAML]);

  const handleSave = async () => {
    const validated = validatedState;
    if (!validated) return;
    setImportState('importing');
    const created = await createWorkflowFrom(() => validated);
    if (!created) {
      // createWorkflowFrom already showed the relevant alert (not
      // connected / failed to create / persistent Retry toast); keep the
      // modal usable either way.
      setImportState('valid');
      return;
    }
    setYamlContent('');
    setValidatedState(null);
    onClose();
    onSuccess();
  };

  const isButtonDisabled =
    importState === 'initial' ||
    importState === 'parsing' ||
    importState === 'invalid' ||
    importState === 'importing';

  const buttonText =
    importState === 'parsing'
      ? 'Validating...'
      : importState === 'importing'
        ? 'Importing...'
        : 'Create';

  const tooltipMessage =
    importState === 'initial'
      ? 'Enter YAML content to create workflow'
      : importState === 'invalid'
        ? 'Fix validation errors to continue'
        : null;

  return (
    <div className="flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between px-6 py-5">
        <h2 className="text-xl text-gray-900">Import a workflow</h2>
        <button
          type="button"
          onClick={() => setMode(mode === 'upload' ? 'paste' : 'upload')}
          className="rounded-full border border-gray-300 px-4 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50 transition-colors"
        >
          {mode === 'upload' ? 'Paste text' : 'Upload a file'}
        </button>
      </div>

      {/* Content area */}
      <div className="h-80 px-6 pb-4">
        {mode === 'upload' ? (
          <YAMLFileDropzone onUpload={handleFileUpload} />
        ) : (
          <YAMLCodeEditor
            value={yamlContent}
            onChange={handleYAMLChange}
            isValidating={importState === 'parsing'}
          />
        )}
      </div>

      {errors.length > 0 && (
        <div className="px-6 pb-3">
          <ValidationErrorDisplay errors={errors} />
        </div>
      )}

      {/* Footer */}
      <div className="flex items-center justify-between px-6 py-5 border-t border-gray-100">
        <button
          type="button"
          onClick={onClose}
          className="text-sm font-medium text-gray-700 hover:text-gray-900"
        >
          Cancel
        </button>
        <Tooltip content={tooltipMessage} side="top">
          <span>
            <button
              type="button"
              onClick={() => {
                void handleSave();
              }}
              disabled={isButtonDisabled}
              className="rounded-full bg-gray-900 px-5 py-2 text-sm font-semibold text-white hover:bg-gray-700 disabled:hover:bg-gray-900 disabled:opacity-40 disabled:cursor-not-allowed inline-flex items-center gap-2 transition-colors"
            >
              {(importState === 'parsing' || importState === 'importing') && (
                <svg
                  className="animate-spin h-4 w-4"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <circle
                    className="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    strokeWidth="4"
                  ></circle>
                  <path
                    className="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  ></path>
                </svg>
              )}
              {buttonText}
            </button>
          </span>
        </Tooltip>
      </div>
    </div>
  );
}
