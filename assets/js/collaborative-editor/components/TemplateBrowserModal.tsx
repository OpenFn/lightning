import { Dialog, DialogBackdrop, DialogPanel } from '@headlessui/react';
import { useEffect, useMemo, useState } from 'react';

import { Tooltip } from '#/components/Tooltip';
import { cn } from '#/utils/cn';

import {
  isBaseTemplate,
  type Template,
  type WorkflowTemplate,
} from '../types/template';
import { filterTemplates, matchesQuery } from '../utils/filterTemplates';
import { tryTemplateToWorkflowState } from '../utils/templateWorkflowState';

import { ActionButton } from './ds/ActionButton';
import { PreviewMessage, WorkflowPreview } from './WorkflowPreview';

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

  // The modal stays mounted between opens, so the previous selection would
  // otherwise still be here next time. Clearing on open hands the choice back
  // to the effect below, which points the preview at the first visible
  // template.
  useEffect(() => {
    if (isOpen) setPreviewedId(null);
  }, [isOpen]);

  // Never show an empty preview pane if there is something to show. Covers both
  // the initial open and a search having just hidden the previewed template.
  const firstVisibleId = visibleTemplates[0]?.id ?? null;
  const hasPreview = previewed !== null;
  useEffect(() => {
    if (!isOpen || hasPreview || firstVisibleId === null) return;
    setPreviewedId(firstVisibleId);
  }, [isOpen, hasPreview, firstVisibleId]);

  // The one parse the modal does. It answers both questions at once — what the
  // preview draws, and whether Create is worth offering — so the diagram and
  // the button can't disagree about which templates are broken. Creating parses
  // again on purpose: that parse mints the ids the new workflow is built from,
  // and reusing these would give two workflows the same job ids.
  const parsed = useMemo(
    () => (previewed ? tryTemplateToWorkflowState(previewed) : null),
    [previewed]
  );

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

          {/* Two panes: list on the left, preview on the right. The gutter
              between them is split evenly either side of the scrollbar: the
              list's own pr-1 on one side, this gap-1 on the other, so the
              scrollbar's lane sits centred in the gutter rather than pressed
              against one edge of it. */}
          <div className="flex flex-1 min-h-0 gap-1 px-4 pb-4">
            {/* List pane. The search sits above the scrolling box rather than
                inside it, so the scrollbar's track starts at the first card
                instead of running the column's full height — and so the input
                can't drift on an overscroll bounce the way a sticky one does.
                The cost is that nothing narrows the input by the scrollbar's
                width, so it carries that width itself: 15px is the list's own
                pr-1 plus the 11px a thin scrollbar takes in Chrome. Change one
                and change the other, or the two right edges drift apart. */}
            <div className="relative w-72 shrink-0 flex flex-col min-h-0">
              <div className="relative mb-4 pr-3.75">
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
                    focus:outline-none focus-visible:ring-0 focus-visible:border-gray-500 focus-visible:ring-gray-500
                    disabled:opacity-50"
                />
              </div>

              <div className="flex-1 min-h-0 overflow-y-auto thin-scrollbar pr-1">
                {loading ? (
                  <p className="py-8 text-center text-sm text-gray-500">
                    Loading templates...
                  </p>
                ) : (
                  /* pb-1 leaves room for the last card's focus ring, which the
                     scroll container would otherwise clip. */
                  <div className="flex flex-col gap-2 pb-1">
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

              {/* Fades the list out at its bottom edge, so a card cut off by
                  the fold reads as "there is more" rather than as the end.
                  Sits over the scroll box rather than masking it, which leaves
                  the scrollbar — painted above page content by the browser —
                  crisp. Harmless when the list is short: the bottom of the box
                  is then empty white, and white over white shows nothing. */}
              <div
                aria-hidden="true"
                className="pointer-events-none absolute inset-x-0 bottom-0 h-16 bg-linear-to-t from-white to-transparent"
              />
            </div>

            {/* Preview pane */}
            <div className="flex flex-1 min-w-0 flex-col rounded-lg border border-gray-200 bg-gray-50 overflow-clip">
              <div className="flex-1 min-h-0">
                {parsed?.state ? (
                  // Keyed so a template switch remounts rather than trying to
                  // animate one graph into another. That means each selection
                  // lays out from scratch, which is cheap at template scale (a
                  // handful of nodes) and keeps the preview free of any
                  // carried-over viewport or node state.
                  <WorkflowPreview key={previewed?.id} state={parsed.state} />
                ) : parsed ? (
                  <PreviewMessage
                    message="This template can't be previewed."
                    detail={parsed.error}
                  />
                ) : (
                  <PreviewMessage message="Select a template to preview it." />
                )}
              </div>

              {previewed && (
                <div className="flex items-center justify-between bg-white gap-14 p-4">
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium text-gray-900">
                      {previewed.name}
                    </p>
                    {/* Two lines tall whatever the description says, and
                        rendered even when there isn't one. This footer is a
                        sibling of the diagram, so any change in its height
                        resizes the canvas — and the preview refits itself at a
                        different zoom as you click down the list. */}
                    <p className="mt-0.5 line-clamp-2 min-h-[2lh] text-sm text-gray-500">
                      {previewed.description}
                    </p>
                  </div>
                  {/* Wrapped in a span because a disabled button emits no
                      pointer events for the tooltip to hang off. */}
                  <Tooltip
                    content={
                      parsed?.error ? "This template can't be read." : null
                    }
                    side="top"
                  >
                    <span className="shrink-0">
                      <ActionButton
                        onClick={() => onCreate(previewed)}
                        disabled={isSaving || parsed?.error != null}
                        loading={isSaving}
                      >
                        {isSaving ? 'Creating...' : 'Create'}
                      </ActionButton>
                    </span>
                  </Tooltip>
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
        'w-full text-left rounded-lg border bg-white p-4 transition-colors',
        'disabled:opacity-50 disabled:cursor-not-allowed',
        'focus:outline-none focus-visible:ring-1 focus-visible:ring-gray-300',
        selected
          ? 'border-gray-500 ring-gray-500'
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
