/**
 * YAMLImportPanel - YAML-based workflow import
 *
 * Architecture:
 * - Supports drag-drop and manual YAML editing
 * - State machine: initial -> parsing -> valid/invalid -> importing
 */

import pDebounce from 'p-debounce';
import { useState, useCallback, useContext, useEffect, useRef } from 'react';

import type { WorkflowState as YAMLWorkflowState } from '../../../yaml/types';
import {
  parseWorkflowYAML,
  convertWorkflowSpecToState,
} from '../../../yaml/util';
import { WorkflowError } from '../../../yaml/workflow-errors';
import { StoreContext } from '../../contexts/StoreProvider';
import { useUICommands } from '../../hooks/useUI';
import { Tooltip } from '../Tooltip';
import { ValidationErrorDisplay } from '../yaml-import/ValidationErrorDisplay';
import { YAMLCodeEditor } from '../yaml-import/YAMLCodeEditor';
import { YAMLFileDropzone } from '../yaml-import/YAMLFileDropzone';

// Import state is managed in UI store - see UIState['importPanel']['importState']

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
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error('YAMLImportPanel must be used within StoreContext');
  }
  const uiStore = context.uiStore;

  const { collapseCreateWorkflowPanel } = useUICommands();

  // Get persisted state from store
  const storedYamlContent = uiStore.withSelector(
    state => state.importPanel.yamlContent
  )();
  const importState = uiStore.withSelector(
    state => state.importPanel.importState
  )();
  const setImportState = uiStore.setImportState;

  const [yamlContent, setYamlContent] = useState(storedYamlContent);
  const [errors, setErrors] = useState<WorkflowError[]>([]);
  const [validatedState, setValidatedState] =
    useState<YAMLWorkflowState | null>(null);

  // Debounced validation and preview (300ms)
  const validateYAML = useCallback(
    pDebounce((content: string) => {
      if (!content.trim()) {
        setImportState('initial');
        setErrors([]);
        setValidatedState(null);
        // Clear canvas when YAML is cleared
        onImport({
          id: '',
          name: '',
          jobs: [],
          triggers: [],
          edges: [],
          positions: null,
        });
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
        // Clear canvas when YAML is invalid
        onImport({
          id: '',
          name: '',
          jobs: [],
          triggers: [],
          edges: [],
          positions: null,
        });
      }
    }, 300),
    [onImport]
  );

  const handleYAMLChange = (content: string) => {
    setYamlContent(content);
    uiStore.setImportYamlContent(content);
    void validateYAML(content);
  };

  const handleFileUpload = (content: string) => {
    setYamlContent(content);
    uiStore.setImportYamlContent(content);
    void validateYAML(content);
  };

  // Restore and validate stored YAML on mount
  const hasRestoredRef = useRef(false);
  useEffect(() => {
    if (hasRestoredRef.current) return;
    hasRestoredRef.current = true;

    if (storedYamlContent) {
      void validateYAML(storedYamlContent);
    }
  }, [storedYamlContent, validateYAML]);

  const handleSave = async () => {
    if (!validatedState) {
      return;
    }

    // Set importing state to show spinner
    setImportState('importing');

    try {
      await onSave();

      // Reset state after successful save
      setYamlContent('');
      setValidatedState(null);
      setImportState('initial');
      uiStore.clearImportPanel();

      // Collapse panel after successful save
      collapseCreateWorkflowPanel();
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

  const tooltipMessage =
    importState === 'initial'
      ? 'Enter YAML content to create workflow'
      : importState === 'invalid'
        ? 'Fix validation errors to continue'
        : null;

  return (
    <div className="w-full h-full flex flex-col bg-white border-r border-gray-200 shadow-xl">
      {/* Header */}
      <div className="shrink-0 px-4 py-4 border-b border-gray-200">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold text-gray-900">
            Import workflow
          </h2>
          <button
            type="button"
            onClick={collapseCreateWorkflowPanel}
            className="rounded hover:bg-gray-100 transition-colors"
            aria-label="Collapse panel"
          >
            <span className="hero-chevron-left h-5 w-5 text-gray-600" />
          </button>
        </div>
      </div>

      {/* Error Banner */}
      {errors.length > 0 && (
        <div className="shrink-0 px-4 pt-4">
          <ValidationErrorDisplay errors={errors} />
        </div>
      )}

      {/* Content Area - Flex column */}
      <div className="flex-1 flex flex-col px-4 py-4 space-y-4 overflow-hidden">
        {/* File Dropzone */}
        <div className="shrink-0">
          <YAMLFileDropzone onUpload={handleFileUpload} />
        </div>

        {/* OR Divider */}
        <div className="relative shrink-0">
          <div className="absolute inset-0 flex items-center">
            <div className="w-full border-t border-gray-300" />
          </div>
          <div className="relative flex justify-center text-sm">
            <span className="bg-white px-2 text-gray-500">OR</span>
          </div>
        </div>

        {/* YAML Editor - Takes remaining space */}
        <div className="flex-1 min-h-0">
          <YAMLCodeEditor
            value={yamlContent}
            onChange={handleYAMLChange}
            isValidating={importState === 'parsing'}
          />
        </div>
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
        <Tooltip content={tooltipMessage} side="bottom">
          <span className="inline-block">
            <button
              type="button"
              onClick={handleSave}
              disabled={isButtonDisabled}
              className="rounded-md bg-primary-600 px-4 py-2 text-sm font-semibold text-white shadow-xs hover:bg-primary-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600 inline-flex items-center gap-x-1.5 transition-colors disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:bg-primary-600"
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
