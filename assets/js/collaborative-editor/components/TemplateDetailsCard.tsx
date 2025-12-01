/**
 * TemplateDetailsCard - Shows selected template details on canvas
 * Appears when a template is selected, similar to legacy workflow editor
 */

import type { Template } from '../types/template';

interface TemplateDetailsCardProps {
  template: Template | null;
}

export function TemplateDetailsCard({ template }: TemplateDetailsCardProps) {
  if (!template) {
    return null;
  }

  return (
    <div className="absolute top-4 left-4 right-4 z-40 bg-white/50 border border-gray-200 rounded-lg p-4 shadow-xs">
      <h3 className="text-sm font-medium text-gray-900 mb-1">
        {template.name}
      </h3>
      <p className="text-sm text-gray-600">
        {template.description || 'No description provided'}
      </p>
    </div>
  );
}
