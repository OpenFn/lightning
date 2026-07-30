import { Dialog, DialogBackdrop, DialogPanel } from '@headlessui/react';

import { cn } from '#/utils/cn';

import type {
  BaseTemplate,
  Template,
  WorkflowTemplate,
} from '../types/template';
import { filterTemplates, matchesQuery } from '../utils/filterTemplates';

export interface TemplateBrowserModalProps {
  isOpen: boolean;
  onClose: () => void;
  templates: Template[];
  loading?: boolean;
  isSaving?: boolean;
  onSelect: (template: Template) => void;
  searchQuery: string;
  onSearchChange: (query: string) => void;
}

export function TemplateBrowserModal({
  isOpen,
  onClose,
  templates,
  loading = false,
  isSaving = false,
  onSelect,
  searchQuery,
  onSearchChange,
}: TemplateBrowserModalProps) {
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

  let cols = 1;
  if (templates.length > 6) cols = 3;
  else if (templates.length > 3) cols = 2;

  return (
    <Dialog
      open={isOpen}
      onClose={onClose}
      className="relative z-20"
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
            'bg-white rounded-2xl shadow-2xl w-full flex flex-col h-[560px]',
            'data-closed:opacity-0 data-closed:scale-95',
            'data-enter:duration-300 data-enter:ease-out',
            'data-leave:duration-200 data-leave:ease-in',
            {
              'max-w-lg': cols === 1,
              'max-w-2xl': cols === 2,
              'max-w-[784px]': cols === 3,
            }
          )}
        >
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-5">
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

          {/* Search bar — fixed, does not scroll */}
          <div className="px-6">
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

          {/* Content — scrollable, fills remaining panel height */}
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
                    onClick={() => onSelect(template)}
                  />
                ))}
                {filteredUserTemplates.map(template => (
                  <TemplateSelectCard
                    key={template.id}
                    template={template}
                    disabled={isSaving}
                    onClick={() => onSelect(template)}
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
        </DialogPanel>
      </div>
    </Dialog>
  );
}

interface TemplateSelectCardProps {
  template: Template;
  disabled: boolean;
  onClick: () => void;
}

function TemplateSelectCard({
  template,
  disabled,
  onClick,
}: TemplateSelectCardProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="w-full h-full text-left rounded-lg border border-gray-200 bg-white p-3
        hover:border-gray-300 hover:bg-gray-50 transition-colors
        disabled:opacity-50 disabled:cursor-not-allowed
        focus:outline-none focus-visible:ring-1 focus-visible:ring-gray-300 focus-visible:border-gray-300"
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
