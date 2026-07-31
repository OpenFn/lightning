import { Dialog, DialogBackdrop, DialogPanel } from '@headlessui/react';
import { useEffect, useState } from 'react';

import { cn } from '#/utils/cn';

import {
  isBaseTemplate,
  type Template,
  type WorkflowTemplate,
} from '../types/template';
import { filterTemplates, matchesQuery } from '../utils/filterTemplates';

import { ActionButton } from './ds/ActionButton';
import { TemplatePreview } from './TemplatePreview';

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
  const baseTemplates = templates.filter(isBaseTemplate);
  const userTemplates = templates.filter(
    (t): t is WorkflowTemplate => !isBaseTemplate(t)
  );
  const q = searchQuery.trim();
  const filteredUserTemplates = filterTemplates(userTemplates, q);
  const anyBaseTemplateMatches =
    q.length > 0 && baseTemplates.some(t => matchesQuery(t, q));

  // Which template the preview pane is showing. Local rather than in UIStore:
  // nothing outside this modal observes it, and it is meant to die with the
  // modal. UIStore holds the fetched templates and the search query because
  // those are shared and survive a close; this does not.
  const [previewedId, setPreviewedId] = useState<string | null>(null);

  // Base templates are always listed, search or not — they are the starting
  // points we want to keep offering. Only user templates get filtered.
  const visibleTemplates = [...baseTemplates, ...filteredUserTemplates];

  // Only ever preview something the list is actually showing — otherwise a
  // search that hides the previewed template leaves the pane, and the create
  // button, pointing at a template the user can no longer see.
  const previewed = visibleTemplates.find(t => t.id === previewedId) ?? null;

  // The modal stays mounted, so reset on close rather than on unmount.
  useEffect(() => {
    if (!isOpen) setPreviewedId(null);
  }, [isOpen]);

  // Never show an empty preview pane if there is something to show. Covers both
  // the initial open and a search having just hidden the previewed template.
  const firstVisibleId = visibleTemplates[0]?.id ?? null;
  const hasPreview = previewed !== null;
  useEffect(() => {
    if (!isOpen || hasPreview || firstVisibleId === null) return;
    setPreviewedId(firstVisibleId);
  }, [isOpen, hasPreview, firstVisibleId]);

  return (
    <Dialog
      open={isOpen}
      onClose={onClose}
      className="relative z-110"
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
            'bg-white rounded-2xl shadow-2xl w-full flex flex-col h-[95%] max-h-180 max-w-5xl',
            'data-closed:opacity-0 data-closed:scale-95',
            'data-enter:duration-300 data-enter:ease-out',
            'data-leave:duration-200 data-leave:ease-in'
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

          {/* Two panes: list on the left, preview on the right */}
          <div className="flex flex-1 min-h-0 gap-5 px-6 pb-6">
            {/* List pane */}
            <div className="flex w-72 shrink-0 flex-col min-h-0">
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

              <div className="mt-4 flex-1 min-h-0 overflow-y-auto thin-scrollbar pr-2">
                {loading ? (
                  <p className="py-8 text-center text-sm text-gray-500">
                    Loading templates...
                  </p>
                ) : (
                  <div className="flex flex-col gap-4 py-1">
                    {visibleTemplates.map(template => (
                      <TemplateSelectCard
                        key={template.id}
                        template={template}
                        selected={template.id === previewedId}
                        disabled={isSaving}
                        onClick={() => setPreviewedId(template.id)}
                      />
                    ))}
                    {userTemplates.length > 0 &&
                      filteredUserTemplates.length === 0 &&
                      searchQuery.trim() &&
                      !anyBaseTemplateMatches && (
                        <p className="py-2 text-sm text-gray-500">
                          No saved templates match your search.
                        </p>
                      )}
                  </div>
                )}
              </div>
            </div>

            {/* Preview pane */}
            <div className="flex flex-1 min-w-0 flex-col rounded-lg border border-gray-200 bg-gray-50">
              <div className="flex-1 min-h-0">
                {previewed ? (
                  // Keyed so a template switch remounts rather than trying to
                  // animate one graph into another. That means each selection
                  // re-parses and re-lays-out from scratch, which is cheap at
                  // template scale (a handful of nodes) and keeps the preview
                  // free of any carried-over viewport or node state.
                  <TemplatePreview key={previewed.id} template={previewed} />
                ) : (
                  <div className="flex h-full items-center justify-center p-6">
                    <p className="text-sm text-gray-500">
                      Select a template to preview it.
                    </p>
                  </div>
                )}
              </div>

              {previewed && (
                <div className="flex items-center justify-between gap-4 border-t border-gray-200 bg-white/60 px-4 py-3">
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium text-gray-900">
                      {previewed.name}
                    </p>
                    {previewed.description && (
                      <p className="mt-0.5 line-clamp-2 text-sm text-gray-500">
                        {previewed.description}
                      </p>
                    )}
                  </div>
                  <ActionButton
                    onClick={() => onSelect(previewed)}
                    disabled={isSaving}
                    loading={isSaving}
                    className="shrink-0"
                  >
                    {isSaving ? 'Creating...' : 'Create'}
                  </ActionButton>
                </div>
              )}
            </div>
          </div>
        </DialogPanel>
      </div>
    </Dialog>
  );
}

interface TemplateSelectCardProps {
  template: Template;
  selected: boolean;
  disabled: boolean;
  onClick: () => void;
}

function TemplateSelectCard({
  template,
  selected,
  disabled,
  onClick,
}: TemplateSelectCardProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-pressed={selected}
      className={cn(
        'w-full text-left rounded-lg border bg-white p-3 transition-colors',
        'disabled:opacity-50 disabled:cursor-not-allowed',
        'focus:outline-none focus-visible:ring-1 focus-visible:ring-gray-300',
        selected
          ? 'border-gray-400 ring-gray-400'
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
