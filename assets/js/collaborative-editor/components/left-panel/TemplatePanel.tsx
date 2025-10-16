/**
 * TemplatePanel - Template-based workflow creation
 *
 * Architecture:
 * - Shows template selection UI (placeholder for now)
 * - Footer has Import button to switch to YAML import mode
 */

interface TemplatePanelProps {
  onImportClick: () => void;
}

export function TemplatePanel({ onImportClick }: TemplatePanelProps) {
  return (
    <div className="w-full h-full flex flex-col bg-white border-r border-gray-200">
      {/* Header */}
      <div className="shrink-0 px-4 py-4 border-b border-gray-200">
        <h2 className="text-lg font-semibold text-gray-900">
          Create New Workflow
        </h2>
      </div>

      {/* Content Area - Templates placeholder */}
      <div className="flex-1 overflow-y-auto px-4 py-6">
        <div className="flex items-center justify-center h-full">
          <div className="text-center text-gray-500">
            <p className="text-base">Create via templates here</p>
            <p className="text-sm mt-2">Template selection coming soon...</p>
          </div>
        </div>
      </div>

      {/* Footer - Fixed */}
      <div className="shrink-0 border-t border-gray-200 px-4 py-4 flex justify-end gap-2">
        <button
          type="button"
          onClick={onImportClick}
          className="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 inline-flex items-center gap-x-2"
        >
          <span className="hero-document-arrow-up size-5" />
          Import
        </button>
      </div>
    </div>
  );
}
