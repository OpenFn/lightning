import { Dialog, DialogBackdrop, DialogPanel } from '@headlessui/react';
import pDebounce from 'p-debounce';
import { useState, useCallback, useRef } from 'react';

import { Tooltip } from '../../components/Tooltip';
import type { WorkflowState as YAMLWorkflowState } from '../../yaml/types';
import { parseWorkflowYAML, convertWorkflowSpecToState } from '../../yaml/util';
import { WorkflowError } from '../../yaml/workflow-errors';
import { useShowYAMLImportModal, useUICommands } from '../hooks/useUI';
import { useCreateWorkflowFlow } from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';

import { ActionButton } from './ds/ActionButton';
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
      className="relative z-110"
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

  const [importState, setImportState] = useState<
    'initial' | 'parsing' | 'valid' | 'invalid' | 'importing'
  >('initial');
  const [yamlContent, setYamlContent] = useState('');
  const [errors, setErrors] = useState<WorkflowError[]>([]);
  const [validatedState, setValidatedState] =
    useState<YAMLWorkflowState | null>(null);
  const [mode, setMode] = useState<'upload' | 'paste'>('upload');
  const validationVersion = useRef(0);

  const debouncedValidate = useRef(
    pDebounce((content: string, version: number) => {
      if (version !== validationVersion.current) return;

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
    const version = ++validationVersion.current;
    void debouncedValidate.current(content, version);
  }, []);

  const handleYAMLChange = (content: string) => {
    setYamlContent(content);
    setImportState(content.trim() ? 'parsing' : 'initial');
    setErrors([]);
    setValidatedState(null);
    void validateYAML(content);
  };

  const handleFileUpload = (content: string) => {
    setMode('paste');
    handleYAMLChange(content);
  };

  const handleModeToggle = () => {
    setMode(mode === 'upload' ? 'paste' : 'upload');
    setYamlContent('');
    setImportState('initial');
    setErrors([]);
    setValidatedState(null);
    validationVersion.current += 1;
  };

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
        <h2 className="text-xl font-medium text-gray-900">Import a workflow</h2>
        <button
          type="button"
          onClick={handleModeToggle}
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
            <ActionButton
              onClick={() => {
                void handleSave();
              }}
              disabled={isButtonDisabled}
              loading={importState === 'parsing' || importState === 'importing'}
            >
              {buttonText}
            </ActionButton>
          </span>
        </Tooltip>
      </div>
    </div>
  );
}
