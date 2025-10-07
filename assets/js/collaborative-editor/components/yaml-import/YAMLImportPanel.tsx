/**
 * YAMLImportPanel - Slide-in panel for importing workflows from YAML
 *
 * Architecture:
 * - Slides in from left (mirrors Inspector on right)
 * - URL-controlled via ?method=import
 * - Width: 33% of viewport
 * - Supports drag-drop and manual YAML editing
 */

import { useState } from 'react';
import type { WorkflowState } from '../../../yaml/types';
import { parseWorkflowYAML, convertWorkflowSpecToState } from '../../../yaml/util';
import { WorkflowError } from '../../../yaml/workflow-errors';

import { YAMLCodeEditor } from './YAMLCodeEditor';
import { YAMLFileDropzone } from './YAMLFileDropzone';
import { ValidationErrorDisplay } from './ValidationErrorDisplay';

interface YAMLImportPanelProps {
  isOpen: boolean;
  onClose: () => void;
  onImport: (workflowState: WorkflowState) => void;
}

export function YAMLImportPanel({ isOpen, onClose, onImport }: YAMLImportPanelProps) {
  const [yamlContent, setYamlContent] = useState('');
  const [errors, setErrors] = useState<WorkflowError[]>([]);
  const [isValidating, setIsValidating] = useState(false);
  const [isValid, setIsValid] = useState(false);

  // Validate YAML whenever content changes
  const validateYAML = (content: string) => {
    if (!content.trim()) {
      setErrors([]);
      setIsValid(false);
      return;
    }

    setIsValidating(true);
    try {
      const spec = parseWorkflowYAML(content);
      convertWorkflowSpecToState(spec); // Validate transformation
      setErrors([]);
      setIsValid(true);
    } catch (error) {
      if (error instanceof WorkflowError) {
        setErrors([error]);
      } else {
        console.error('Unexpected validation error:', error);
        setErrors([]);
      }
      setIsValid(false);
    } finally {
      setIsValidating(false);
    }
  };

  const handleYAMLChange = (content: string) => {
    setYamlContent(content);
    validateYAML(content);
  };

  const handleFileUpload = (content: string) => {
    setYamlContent(content);
    validateYAML(content);
  };

  const handleImport = () => {
    if (!isValid || !yamlContent) return;

    try {
      const spec = parseWorkflowYAML(yamlContent);
      const workflowState = convertWorkflowSpecToState(spec);
      onImport(workflowState);
      onClose();
    } catch (error) {
      if (error instanceof WorkflowError) {
        setErrors([error]);
      }
    }
  };

  return (
    <div
      className={`absolute top-0 left-0 h-full w-1/3 transition-transform duration-300 ease-in-out z-10 ${
        isOpen ? 'translate-x-0' : '-translate-x-full pointer-events-none'
      }`}
    >
      <div className="pointer-events-auto w-full h-full flex flex-col bg-white border-r border-gray-200 shadow-xl">
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-4 border-b border-gray-200">
          <h2 className="text-base font-semibold text-gray-900">
            Import Workflow from YAML
          </h2>
          <button
            type="button"
            onClick={onClose}
            className="rounded-md text-gray-400 hover:text-gray-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
          >
            <span className="sr-only">Close panel</span>
            <div className="hero-x-mark size-6" />
          </button>
        </div>

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
            isValidating={isValidating}
          />
        </div>

        {/* Footer - Fixed */}
        <div className="shrink-0 border-t border-gray-200 px-4 py-4 flex justify-end gap-2">
          <button
            type="button"
            onClick={onClose}
            className="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleImport}
            disabled={!isValid || isValidating}
            className="rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isValidating ? 'Validating...' : 'Import Workflow'}
          </button>
        </div>
      </div>
    </div>
  );
}
