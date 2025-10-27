/**
 * YAMLImportPanel - YAML-based workflow import
 *
 * Architecture:
 * - Supports drag-drop and manual YAML editing
 * - State machine: initial -> parsing -> valid/invalid -> importing
 */

import pDebounce from 'p-debounce';
import { useState, useCallback } from 'react';

import type { WorkflowState as YAMLWorkflowState } from '../../../yaml/types';
import {
  parseWorkflowYAML,
  convertWorkflowSpecToState,
} from '../../../yaml/util';
import { WorkflowError } from '../../../yaml/workflow-errors';
import { ValidationErrorDisplay } from '../yaml-import/ValidationErrorDisplay';
import { YAMLCodeEditor } from '../yaml-import/YAMLCodeEditor';
import { YAMLFileDropzone } from '../yaml-import/YAMLFileDropzone';

/**
 * Import state machine:
 * - initial: No content, button disabled
 * - parsing: Validating YAML, button shows spinner
 * - valid: Valid YAML, button enabled
 * - invalid: Invalid YAML, button disabled
 * - importing: Import in progress, button shows spinner
 */
type ImportState = 'initial' | 'parsing' | 'valid' | 'invalid' | 'importing';

interface YAMLImportPanelProps {
  onImport: (workflowState: YAMLWorkflowState) => void;
  onSave: () => Promise<unknown>;
  onBack: () => void;
}

export function YAMLImportPanel({
  onImport,
  onSave,
  onBack,
}: YAMLImportPanelProps) {
  const [yamlContent, setYamlContent] = useState('');
  const [errors, setErrors] = useState<WorkflowError[]>([]);
  const [importState, setImportState] = useState<ImportState>('initial');
  const [validatedState, setValidatedState] =
    useState<YAMLWorkflowState | null>(null);

  // Debounced validation and preview (300ms)
  const validateYAML = useCallback(
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

        // Automatically preview the workflow in the diagram
        onImport(state);
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
    }, 300),
    [onImport]
  );

  const handleYAMLChange = (content: string) => {
    setYamlContent(content);
    validateYAML(content);
  };

  const handleFileUpload = (content: string) => {
    setYamlContent(content);
    validateYAML(content);
  };

  const handleSave = async () => {
    if (!validatedState) {
      return;
    }

    // Set importing state to show spinner
    setImportState('importing');

    try {
      // Save the workflow (this also closes the panel)
      await onSave();

      // Reset state after successful save
      setYamlContent('');
      setValidatedState(null);
      setImportState('initial');
    } catch (error) {
      // On error, reset to valid state so user can retry
      setImportState('valid');
      console.error('Failed to save workflow:', error);
    }
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

  return (
    <div className="w-full h-full flex flex-col bg-white border-r border-gray-200 shadow-xl">
      {/* Error Banner */}
      {errors.length > 0 && (
        <div className="shrink-0">
          <ValidationErrorDisplay errors={errors} />
        </div>
      )}

      {/* Content Area - Scrollable */}
      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-4">
        {/* File Dropzone */}
        <YAMLFileDropzone onUpload={handleFileUpload} />

        {/* OR Divider */}
        <div className="relative">
          <div className="absolute inset-0 flex items-center">
            <div className="w-full border-t border-gray-300" />
          </div>
          <div className="relative flex justify-center text-sm">
            <span className="bg-white px-2 text-gray-500">OR</span>
          </div>
        </div>

        {/* YAML Editor */}
        <YAMLCodeEditor
          value={yamlContent}
          onChange={handleYAMLChange}
          isValidating={importState === 'parsing'}
        />
      </div>

      {/* Footer - Fixed */}
      <div className="shrink-0 border-t border-gray-200 px-4 py-4 flex justify-end gap-2">
        <button
          type="button"
          onClick={onBack}
          className="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
        >
          Back
        </button>
        <button
          type="button"
          onClick={handleSave}
          disabled={isButtonDisabled}
          className={`rounded-md px-4 py-2 text-sm font-semibold shadow-xs focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 inline-flex items-center gap-x-1.5 transition-colors ${
            isButtonDisabled
              ? 'bg-primary-300 text-white opacity-50 cursor-not-allowed'
              : 'bg-primary-600 text-white hover:bg-primary-700 focus-visible:outline-primary-600'
          }`}
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
      </div>
    </div>
  );
}
