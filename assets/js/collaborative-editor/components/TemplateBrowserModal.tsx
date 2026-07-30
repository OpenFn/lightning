import { Dialog, DialogBackdrop, DialogPanel } from '@headlessui/react';
import { useEffect, useState } from 'react';

import { cn } from '#/utils/cn';

import type {
  BaseTemplate,
  Template,
  WorkflowTemplate,
} from '../types/template';
import { filterTemplates, matchesQuery } from '../utils/filterTemplates';

import { TemplatePreview } from './TemplatePreview';

export interface TemplateBrowserModalProps {
  isOpen: boolean;
  onClose: () => void;
  templates: Template[];
  loading?: boolean;
  isSaving?: boolean;
  onCreate: (template: Template) => void;
  searchQuery: string;
  onSearchChange: (query: string) => void;
}

export function TemplateBrowserModal({
  isOpen,
  onClose,
  templates,
  loading = false,
  isSaving = false,
  onCreate,
  searchQuery,
  onSearchChange,
}: TemplateBrowserModalProps) {
  const [selectedId, setSelectedId] = useState<string | null>(null);

  // The modal stays mounted across opens; drop any stale selection so each
  // open starts back on the first template.
  useEffect(() => {
    if (isOpen) setSelectedId(null);
  }, [isOpen]);

  const baseTemplates = templates.filter(
    (t): t is BaseTemplate => (t as BaseTemplate).isBase === true
  );
  const userTemplates = templates.filter(
    (t): t is WorkflowTemplate => (t as BaseTemplate).isBase !== true
  );
  const q = searchQuery.trim();
  const filteredUserTemplates = filterTemplates(userTemplates, q);
  const anyBaseTemplateMatches =
    q.length > 0 && baseTemplates.some(t => matchesQuery(t, q));

  // Templates are seeded base-first, so this defaults to the first base
  // template until the user picks a card.
  const selectedTemplate =
    templates.find(t => t.id === selectedId) ?? templates[0] ?? null;

  let cols = 1;
  if (templates.length > 6) cols = 3;
  else if (templates.length > 3) cols = 2;

  return (
    <Dialog
      open={isOpen}
      onClose={onClose}
      // Above the app sidebar (z-[100]) — the full-size panel spans under it
      className="relative z-[110]"
      aria-label="Browse workflow templates"
    >
      <DialogBackdrop
        transition
        className="modal-backdrop data-closed:opacity-0 data-enter:duration-300
          data-enter:ease-out data-leave:duration-200 data-leave:ease-in"
      />
      <div className="fixed inset-0 z-10 flex items-center justify-center p-4">
        <DialogPanel
          transition
          className={cn(
            'bg-white rounded-2xl shadow-2xl w-full h-full max-w-6xl max-h-[800px] flex flex-col overflow-hidden',
            'data-closed:opacity-0 data-closed:scale-95',
            'data-enter:duration-300 data-enter:ease-out',
            'data-leave:duration-200 data-leave:ease-in'
          )}
        >
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-5 border-b border-gray-200">
            <h2 className="text-xl font-medium text-gray-900">Templates</h2>
            <button
              type="button"
              onClick={onClose}
              className="rounded-md p-1 text-gray-400 hover:text-gray-600 hover:bg-gray-100 transition-colors"
              aria-label="Close"
            >
              <span className="hero-x-mark h-5 w-5" />
            </button>
          </div>

          {/* Body — template list on the left, preview pane on the right */}
          <div className="flex flex-1 min-h-0">
            <div
              data-testid="template-list-pane"
              className={cn('flex flex-col shrink-0 min-w-0 max-w-[50%]', {
                'w-96': cols === 1,
                'w-[560px]': cols === 2,
                'w-[800px]': cols === 3,
              })}
            >
              {/* Search bar — fixed, does not scroll */}
              <div className="px-6 pt-5">
                <div className="relative">
                  <span className="pointer-events-none absolute inset-y-0 left-3 flex items-center">
                    <span className="hero-magnifying-glass h-4 w-4 text-gray-400" />
                  </span>
                  <input
                    type="text"
                    aria-label="Search templates"
                    placeholder="Search templates"
                    value={searchQuery}
                    onChange={e => onSearchChange(e.target.value)}
                    disabled={loading}
                    className="w-full rounded-md border border-gray-200 py-2 pl-9 pr-3 text-sm
                      text-gray-900 placeholder:text-gray-400
                      focus:outline-none focus-visible:ring-1 focus-visible:border-gray-300 focus-visible:ring-gray-300
                      disabled:opacity-50"
                  />
                </div>
              </div>

              {/* Card grid — scrollable, fills remaining panel height */}
              <div className="px-6 py-5 overflow-y-auto flex-1 min-h-0">
                {loading ? (
                  <p className="text-sm text-gray-500 text-center py-8">
                    Loading templates...
                  </p>
                ) : (
                  <div
                    className={cn('grid gap-x-4 gap-y-6', {
                      'grid-cols-1': cols === 1,
                      'grid-cols-2': cols === 2,
                      'grid-cols-3': cols === 3,
                    })}
                  >
                    {/* Base templates are always shown unfiltered — intentional */}
                    {baseTemplates.map(template => (
                      <TemplateSelectCard
                        key={template.id}
                        template={template}
                        disabled={isSaving}
                        selected={template.id === selectedTemplate?.id}
                        onClick={() => setSelectedId(template.id)}
                      />
                    ))}
                    {filteredUserTemplates.map(template => (
                      <TemplateSelectCard
                        key={template.id}
                        template={template}
                        disabled={isSaving}
                        selected={template.id === selectedTemplate?.id}
                        onClick={() => setSelectedId(template.id)}
                      />
                    ))}
                    {userTemplates.length > 0 &&
                      filteredUserTemplates.length === 0 &&
                      searchQuery.trim() &&
                      !anyBaseTemplateMatches && (
                        <p
                          className={cn('text-sm text-gray-500 py-2', {
                            'col-span-2': cols === 2,
                            'col-span-3': cols === 3,
                          })}
                        >
                          No saved templates match your search.
                        </p>
                      )}
                  </div>
                )}
              </div>
            </div>

            {/* Preview pane */}
            <div className="flex-1 min-w-0 border-l border-gray-200 flex flex-col min-h-0">
              <div className="flex-1 min-h-0" data-testid="template-preview">
                {selectedTemplate ? (
                  <TemplatePreview template={selectedTemplate} />
                ) : (
                  <div className="flex h-full items-center justify-center">
                    <p className="text-sm text-gray-400">
                      Select a template to preview it.
                    </p>
                  </div>
                )}
              </div>
              <div className="border-t border-gray-200 px-5 py-4 flex items-center justify-between gap-3">
                <p className="text-sm font-medium text-gray-900 truncate">
                  {selectedTemplate?.name}
                </p>
                <button
                  type="button"
                  onClick={() => {
                    if (selectedTemplate) onCreate(selectedTemplate);
                  }}
                  disabled={isSaving || !selectedTemplate}
                  className="shrink-0 rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white
                    hover:bg-primary-500
                    disabled:bg-primary-300 disabled:hover:bg-primary-300 disabled:cursor-not-allowed
                    focus:outline-none focus-visible:ring-2 focus-visible:ring-primary-600 focus-visible:ring-offset-2"
                >
                  {isSaving ? 'Creating...' : 'Use this template'}
                </button>
              </div>
            </div>
          </div>
        </DialogPanel>
      </div>
    </Dialog>
  );
}

interface TemplateSelectCardProps {
  template: Template;
  disabled: boolean;
  selected: boolean;
  onClick: () => void;
}

function TemplateSelectCard({
  template,
  disabled,
  selected,
  onClick,
}: TemplateSelectCardProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-pressed={selected}
      className={cn(
        `w-full h-full text-left rounded-lg border bg-white p-3 transition-colors
        disabled:opacity-50 disabled:cursor-not-allowed
        focus:outline-none focus-visible:ring-1 focus-visible:ring-gray-300 focus-visible:border-gray-300`,
        selected
          ? 'border-primary-600 ring-1 ring-primary-600'
          : 'border-gray-200 hover:border-gray-300 hover:bg-gray-50'
      )}
    >
      <p className="text-sm font-medium text-gray-900">{template.name}</p>
      {template.description && (
        <p className="mt-0.5 text-sm text-gray-500 line-clamp-3">
          {template.description}
        </p>
      )}
    </button>
  );
}
