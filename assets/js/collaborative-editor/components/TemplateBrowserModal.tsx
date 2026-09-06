import { Dialog, DialogBackdrop, DialogPanel } from '@headlessui/react';
import { useEffect, useMemo, useState } from 'react';

import { Tooltip } from '#/components/Tooltip';
import { cn } from '#/utils/cn';

import { useOverlayScrollbar } from '../hooks/useOverlayScrollbar';
import { useScrollMetrics } from '../hooks/useScrollMetrics';
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

  // Which template the preview pane is showing. Local rather than in UIStore
  // because nothing outside this modal observes it and it is meant to die with
  // the modal, unlike the fetched templates and the search query.
  const [previewedId, setPreviewedId] = useState<string | null>(null);

  // Base templates are always listed, search or not — they are the starting
  // points we want to keep offering. Only user templates get filtered.
  const visibleTemplates = [...baseTemplates, ...filteredUserTemplates];

  // Only ever preview something the list is actually showing — otherwise a
  // search that hides the previewed template leaves the pane, and the create
  // button, pointing at a template the user can no longer see.
  const previewed = visibleTemplates.find(t => t.id === previewedId) ?? null;

  // The modal stays mounted between opens, so the previous selection would
  // otherwise still be here next time. Clearing hands the choice back to the
  // effect below.
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

  // The list hides its own scrollbar and this draws one in the gutter instead,
  // so the space either side of the cards stays the width it is written as: a
  // native scrollbar takes its width out of the content box, and charges a
  // different amount on each platform. The fade at the bottom of the list reads
  // the same measurements, so the two can't disagree about what is left below.
  const { scrollRef, contentRef, element, metrics, canScrollDown } =
    useScrollMetrics();
  const { thumb, handleThumbPointerDown } = useOverlayScrollbar(
    element,
    metrics
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

          {/* Two panes with a 24px gutter between them, matching the 24px
              outside them and in the header. They stay equal only because the
              list's scrollbar is drawn in the gutter — see the overlay
              scrollbar above. */}
          <div className="flex flex-1 min-h-0 px-6 pb-6">
            {/* List pane. The search scrolls with the list rather than sitting
                above it, so the two share one width and their edges line up by
                construction rather than by matching numbers in two places.
                `overscroll-none` keeps it still during a rubber-band bounce. */}
            <div className="relative w-76 shrink-0 flex flex-col min-h-0">
              {/* `scroll-pt-12` clears the sticky search: without it a card
                  reached by Tab is scrolled flush with the top of the box,
                  which is where the search sits. 48px covers the input and its
                  `pb-2`. */}
              <div
                ref={scrollRef}
                className="flex-1 min-h-0 overflow-y-auto overscroll-none no-scrollbar scroll-pt-12"
              >
                {/* One wrapper around everything scrollable, so the thumb can
                    watch a single element for height changes. Watching the
                    children instead would miss the swap from the loading
                    message to the list. */}
                <div ref={contentRef}>
                  {/* Opaque so cards pass under it rather than through it. */}
                  <div className="sticky top-0 z-10 bg-white pb-2">
                    <div className="relative">
                      <span className="pointer-events-none absolute inset-y-0 left-3 flex items-center">
                        <span className="hero-magnifying-glass h-4 w-4 text-gray-400" />
                      </span>
                      {/* `ring-0` cancels the blue focus ring the forms plugin
                          puts on every text input; the border carries focus
                          here instead. */}
                      <input
                        type="text"
                        aria-label="Search templates"
                        placeholder="Search templates"
                        value={searchQuery}
                        onChange={e => onSearchChange(e.target.value)}
                        disabled={loading}
                        className="w-full rounded-md border border-gray-200 py-2 pl-9 pr-3 text-sm
                        text-gray-900 placeholder:text-gray-400
                        focus:outline-none focus-visible:ring-0 focus-visible:border-gray-500
                        disabled:opacity-50"
                      />
                    </div>
                  </div>

                  {loading ? (
                    <p className="py-8 text-center text-sm text-gray-500">
                      Loading templates...
                    </p>
                  ) : (
                    <div className="flex flex-col gap-2">
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

              {/* The fold at the bottom of the list. Only while there is
                  something below it — over the last card it would just be
                  bleaching a description nothing is hiding — and faded rather
                  than unmounted so it eases away instead of blinking out. */}
              <div
                aria-hidden="true"
                className={cn(
                  `pointer-events-none absolute inset-x-0 bottom-0 h-8
                   bg-linear-to-t from-white to-transparent
                   transition-opacity duration-200`,
                  canScrollDown ? 'opacity-100' : 'opacity-0'
                )}
              />
            </div>

            {/* The gutter, and the scrollbar's home. Making it an element
                rather than a `gap` gives the thumb somewhere to sit that is
                measured from both panes, so it centres between them instead of
                being offset from one by a number that has to be kept in step
                with the padding. */}
            <div className="relative w-6 shrink-0">
              {thumb && (
                <div
                  aria-hidden="true"
                  onPointerDown={handleThumbPointerDown}
                  style={{ top: thumb.top, height: thumb.height }}
                  className="absolute left-1/2 w-1.5 -translate-x-1/2 rounded-full
                    bg-gray-300 transition-colors hover:bg-gray-400"
                />
              )}
            </div>

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
        // Inset because the scroll box clips at its own edge and the cards run
        // its full width, so an outward ring would lose its sides. That puts it
        // against the card's border, which is why it is the focus colour and
        // not a grey: a grey either vanishes into that border or reads as the
        // selected card's.
        'focus:outline-none focus-visible:ring-1 focus-visible:ring-inset focus-visible:ring-primary-600',
        selected
          ? 'border-gray-500'
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
