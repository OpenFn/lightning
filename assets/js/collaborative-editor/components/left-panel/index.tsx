/**
 * LeftPanel - Side panel component for workflow creation methods
 * Shows different creation UIs based on the selected method
 */

import type { WorkflowState as YAMLWorkflowState } from '../../../yaml/types';

import { TemplatePanel } from './TemplatePanel';
import { YAMLImportPanel } from './YAMLImportPanel';

type CreationMethod = 'template' | 'import' | 'ai' | null;

interface LeftPanelProps {
  method: CreationMethod;
  onMethodChange: (method: CreationMethod) => void;
  onImport: (workflowState: YAMLWorkflowState) => void;
  onClosePanel: () => void;
  onSave: () => Promise<unknown>;
}

export function LeftPanel({
  method,
  onMethodChange,
  onImport,
  onSave,
}: LeftPanelProps) {
  // Default to template method when panel is shown without explicit method
  const currentMethod = method || 'template';

  const handleSwitchToImport = () => {
    onMethodChange('import');
  };

  const handleSwicthToTemplate = () => {
    onMethodChange('template');
  };

  // Don't render if no method selected
  if (!method) return null;

  return (
    <div
      className={`absolute inset-y-0 left-0 w-1/3 transition-transform duration-300 ease-in-out z-10 ${
        method ? 'translate-x-0' : '-translate-x-full pointer-events-none'
      }`}
    >
      <div className="pointer-events-auto w-full h-full">
        {currentMethod === 'template' && (
          <TemplatePanel onImportClick={handleSwitchToImport} />
        )}
        {currentMethod === 'import' && (
          <YAMLImportPanel
            onImport={onImport}
            onSave={onSave}
            onBack={handleSwicthToTemplate}
          />
        )}
        {currentMethod === 'ai' && (
          <div className="w-full h-full flex items-center justify-center bg-white border-r border-gray-200">
            <p className="text-gray-500">AI workflow creation coming soon...</p>
          </div>
        )}
      </div>
    </div>
  );
}
