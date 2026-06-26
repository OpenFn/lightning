/**
 * LeftPanel - Side panel component for workflow creation methods
 * Shows different creation UIs based on the selected method
 */

import { TemplatePanel } from './TemplatePanel';

type CreationMethod = 'template' | 'import' | 'ai' | null;

interface LeftPanelProps {
  method: CreationMethod;
  onMethodChange: (method: CreationMethod) => void;
}

export function LeftPanel({ method, onMethodChange }: LeftPanelProps) {
  // Default to template method when panel is shown without explicit method
  const currentMethod = method || 'template';

  const handleSwitchToImport = () => {
    onMethodChange('import');
  };

  // Don't render if no method selected
  if (!method) return null;

  return (
    <div className="w-full h-full">
      {currentMethod === 'template' && (
        <TemplatePanel onImportClick={handleSwitchToImport} />
      )}
      {currentMethod === 'ai' && (
        <div className="w-full h-full flex items-center justify-center bg-white border-r border-gray-200">
          <p className="text-gray-500">AI workflow creation coming soon...</p>
        </div>
      )}
    </div>
  );
}
