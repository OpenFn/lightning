// Modal from a live workflow: create a new sandbox or join an active one; both hard-navigate to the sandbox editor.

import {
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
} from '@headlessui/react';
import { format, formatDistanceToNow } from 'date-fns';
import { useCallback, useEffect, useState } from 'react';

import { cn } from '#/utils/cn';

import { Tooltip } from '../../components/Tooltip';
import { useWorkflowActions } from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';
import {
  formatChannelErrorMessage,
  isChannelRequestError,
} from '../lib/errors';
import { notifications } from '../lib/notifications';
import type { Sandbox } from '../types/workflow';

interface EditInSandboxPickerProps {
  isOpen: boolean;
  onClose: () => void;
}

// Turn an unknown error into a user-facing description. Channel replies carry
// structured field/base errors we can format; anything else gets a generic
// retry hint. Shared by the list-load and create handlers.
function describeSandboxError(error: unknown): string {
  return isChannelRequestError(error)
    ? formatChannelErrorMessage({
        errors: error.errors as { base?: string[] } & Record<string, string[]>,
        type: error.type,
      })
    : 'Please try again.';
}

// Pull a name-field validation message out of a channel error, if present.
// Duplicate names (and other name validations) come back as a validation_error
// keyed under `name`; those render inline under the input. Everything else
// (system/unexpected errors) returns null and is surfaced as a toast instead.
function extractNameFieldError(error: unknown): string | null {
  if (!isChannelRequestError(error)) return null;
  if (error.type !== 'validation_error') return null;

  const nameErrors = error.errors['name'];
  if (!Array.isArray(nameErrors) || !nameErrors[0]) return null;

  const joined = nameErrors.join(', ');

  // The duplicate-name case gets a friendly, product-specific message. Other
  // name validations (blank, too long, invalid) keep their own server message
  // so a different failure is never mislabelled as a duplicate.
  if (/taken/i.test(joined)) {
    return 'A sandbox with this name exists already.';
  }

  return joined;
}

// A joinable sandbox row: the whole row is the click target (joins the
// sandbox). A colour stripe on the left, then the sandbox name over a single
// muted metadata line ("Created {relative} by {owner}"), and a quiet "Join"
// affordance on the right that fills in and reveals an arrow on hover. The
// creation time shows as a relative label with the exact timestamp on hover.
// The owner can be null (unknown), in which case the "by {owner}" suffix is
// omitted.
function SandboxRow({
  sandbox,
  onJoin,
}: {
  sandbox: Sandbox;
  onJoin: (sandbox: Sandbox) => void;
}) {
  const { owner } = sandbox;
  const ownerName = owner ? owner.name || owner.email || '' : '';

  const date = new Date(sandbox.inserted_at);
  const validDate = !Number.isNaN(date.getTime());
  const relative = validDate
    ? formatDistanceToNow(date, { addSuffix: true })
    : '';
  const exact = validDate ? format(date, 'd MMM yyyy, HH:mm') : '';

  // The whole row is the click target. Inner elements are phrasing spans (not
  // <div>/<p>) so the DOM stays valid inside the <button>; the timestamp's
  // Tooltip trigger is a Radix asChild <span>, which is valid nested here too.
  return (
    <li data-testid="sandbox-row">
      <button
        type="button"
        data-testid="join-sandbox-button"
        aria-label={`Join ${sandbox.name}`}
        onClick={() => {
          onJoin(sandbox);
        }}
        className="group -mx-3 flex w-[calc(100%+1.5rem)] items-center
          justify-between gap-4 rounded-lg px-3 py-3 text-left
          transition-colors hover:bg-gray-50 focus-visible:outline-2
          focus-visible:outline-offset-2 focus-visible:outline-primary-600"
      >
        <span className="flex min-w-0 items-center gap-2.5">
          <span
            aria-hidden="true"
            className="h-8 w-1 shrink-0 rounded-full"
            style={{ backgroundColor: sandbox.color ?? '#e5e7eb' }}
          />
          <span className="block min-w-0">
            <span className="block truncate text-sm font-semibold text-gray-900">
              {sandbox.name}
            </span>
            {/* The date never truncates; only the owner name gives way when
                space is tight. Hovering the date reveals the exact timestamp. */}
            <span className="flex min-w-0 items-center gap-1 text-xs text-gray-500">
              <Tooltip content={exact} side="top">
                <span className="shrink-0 whitespace-nowrap">
                  Created {relative}
                </span>
              </Tooltip>
              {owner && ownerName && (
                <>
                  <span className="shrink-0">by</span>
                  <span className="min-w-0 truncate">{ownerName}</span>
                </>
              )}
            </span>
          </span>
        </span>
        <span
          aria-hidden="true"
          className="flex shrink-0 items-center gap-1 text-sm font-medium
            text-gray-400 transition-colors group-hover:text-gray-900"
        >
          Join
          <span
            className="hero-arrow-right-micro h-4 w-4 -translate-x-1 opacity-0
              transition-all group-hover:translate-x-0 group-hover:opacity-100"
          />
        </span>
      </button>
    </li>
  );
}

// Three placeholder rows shown while the sandbox list loads. Mirrors the shape
// of a real row (colour tile + two text lines) so the layout doesn't jump.
function SandboxListSkeleton() {
  return (
    <ul className="mt-3 space-y-1" data-testid="sandbox-list-loading">
      {[0, 1, 2].map(index => (
        <li
          key={index}
          className="-mx-3 flex items-center gap-2.5 px-3 py-3"
          aria-hidden="true"
        >
          <div className="h-8 w-1 shrink-0 animate-pulse rounded-full bg-gray-200" />
          <div className="min-w-0 flex-1 space-y-2">
            <div className="h-3 w-1/3 animate-pulse rounded bg-gray-200" />
            <div className="h-2.5 w-1/2 animate-pulse rounded bg-gray-200" />
          </div>
        </li>
      ))}
    </ul>
  );
}

const navigateToSandbox = (projectId: string, workflowId: string) => {
  window.location.href = `/projects/${projectId}/w/${workflowId}`;
};

export function EditInSandboxPicker({
  isOpen,
  onClose,
}: EditInSandboxPickerProps) {
  const { listSandboxes, editInSandbox } = useWorkflowActions();

  // High-priority Escape handler to prevent closing the parent IDE/inspector.
  // Priority 100 (MODAL) ensures this runs before the IDE handler (priority 50);
  // Headless UI's own Escape handling never fires while those intercept it.
  useKeyboardShortcut(
    'Escape',
    () => {
      onClose();
    },
    100,
    { enabled: isOpen }
  );

  const [name, setName] = useState('');
  const [nameError, setNameError] = useState<string | null>(null);
  const [isCreating, setIsCreating] = useState(false);
  const [isLoadingList, setIsLoadingList] = useState(false);
  const [sandboxes, setSandboxes] = useState<Sandbox[]>([]);

  useEffect(() => {
    if (!isOpen) return;

    let cancelled = false;
    setIsLoadingList(true);
    setSandboxes([]);

    const load = async () => {
      try {
        const result = await listSandboxes();
        if (!cancelled) setSandboxes(result);
      } catch (error) {
        if (!cancelled) {
          notifications.alert({
            title: 'Could not load sandboxes',
            description: describeSandboxError(error),
          });
        }
      } finally {
        if (!cancelled) setIsLoadingList(false);
      }
    };

    void load();

    return () => {
      cancelled = true;
    };
  }, [isOpen, listSandboxes]);

  const handleCreate = useCallback(() => {
    setIsCreating(true);
    setNameError(null);
    const trimmed = name.trim();

    const create = async () => {
      try {
        const { project_id, workflow_id } = await editInSandbox(trimmed);
        navigateToSandbox(project_id, workflow_id);
      } catch (error) {
        // A rejected name (duplicate, invalid) belongs under the input as an
        // inline field error; only genuinely unexpected/system errors toast.
        const fieldError = extractNameFieldError(error);
        if (fieldError) {
          setNameError(fieldError);
        } else {
          notifications.alert({
            title: 'Could not create a sandbox',
            description: describeSandboxError(error),
          });
        }
        setIsCreating(false);
      }
    };

    void create();
  }, [name, editInSandbox]);

  const handleJoin = useCallback((sandbox: Sandbox) => {
    if (!sandbox.workflow_id) return;
    navigateToSandbox(sandbox.id, sandbox.workflow_id);
  }, []);

  // A name is required to create. The server already returns only joinable
  // sandboxes (each holding a clone of this workflow), so the list is rendered
  // as-is.
  const canCreate = name.trim().length > 0;

  return (
    <Dialog
      open={isOpen}
      onClose={onClose}
      className="relative z-[60]"
      data-testid="edit-in-sandbox-picker"
    >
      <DialogBackdrop
        transition
        className="modal-backdrop data-closed:opacity-0 data-enter:duration-300
          data-enter:ease-out data-leave:duration-200 data-leave:ease-in"
      />

      <div className="fixed inset-0 z-10 w-screen overflow-y-auto">
        <div
          className="flex min-h-full items-end justify-center p-4 text-center
            sm:items-center sm:p-0"
        >
          <DialogPanel
            transition
            className="relative transform overflow-hidden rounded-lg bg-white
              px-4 pb-4 pt-5 text-left shadow-xl transition-all
              data-closed:translate-y-4 data-closed:opacity-0
              data-enter:duration-300 data-enter:ease-out
              data-leave:duration-200 data-leave:ease-in sm:my-8 sm:w-full
              sm:max-w-lg sm:p-6"
          >
            <button
              type="button"
              onClick={onClose}
              aria-label="Close"
              className="absolute right-4 top-4 sm:right-6 sm:top-6 rounded-md
                p-1 text-gray-400
                transition-colors hover:text-gray-600 focus-visible:outline-2
                focus-visible:outline-offset-2 focus-visible:outline-primary-600"
            >
              <span
                className="hero-x-mark h-5 w-5"
                aria-hidden="true"
                role="img"
              />
            </button>

            <DialogTitle
              as="h3"
              className="text-base font-semibold text-gray-900"
            >
              Edit in sandbox
            </DialogTitle>
            <p className="mt-1 text-sm text-gray-600">
              Make changes safely in a sandbox without affecting this live
              workflow.
            </p>

            {/* Create a new sandbox. Eyebrow title + subtitle mirror the
                "Join an active sandbox" section below so the two read as
                visual siblings; the title/subtitle/placeholder identify the
                field, so no separate visible label is needed. */}
            <div className="mt-6">
              <p
                className="text-xs font-semibold uppercase tracking-wide
                  text-gray-500"
              >
                Create a new sandbox
              </p>
              <p className="mt-1 text-xs text-gray-500">
                Branch from the current live version to make changes safely.
              </p>
              <form
                className="mt-3"
                onSubmit={event => {
                  event.preventDefault();
                  // Enter can submit even while the button is disabled; honour
                  // the same guards (non-empty name, no create in flight).
                  if (isCreating || !canCreate) return;
                  handleCreate();
                }}
              >
                <div className="flex gap-2">
                  <div className="min-w-0 flex-1">
                    <label htmlFor="sandbox-name" className="sr-only">
                      Sandbox name
                    </label>
                    <input
                      id="sandbox-name"
                      type="text"
                      value={name}
                      onChange={event => {
                        setName(event.target.value);
                        // Editing the name dismisses a stale field error.
                        setNameError(null);
                      }}
                      placeholder="e.g. Test new changes"
                      disabled={isCreating}
                      aria-invalid={nameError ? true : undefined}
                      aria-describedby={
                        nameError ? 'sandbox-name-error' : undefined
                      }
                      className={cn(
                        `block w-full rounded-md border-0 px-3 py-2 text-sm
                          shadow-sm ring-1 ring-inset placeholder:text-gray-400
                          focus:ring-2 focus:ring-inset
                          disabled:cursor-not-allowed disabled:opacity-50`,
                        nameError
                          ? 'text-red-900 ring-red-300 focus:ring-red-500'
                          : 'text-gray-900 ring-gray-300 focus:ring-primary-600'
                      )}
                    />
                  </div>
                  <button
                    type="submit"
                    data-testid="create-sandbox-button"
                    disabled={isCreating || !canCreate}
                    className="inline-flex shrink-0 items-center self-start
                      rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold
                      text-white shadow-sm shadow-primary-600/20
                      hover:bg-primary-500 focus-visible:outline-2
                      focus-visible:outline-offset-2
                      focus-visible:outline-primary-600
                      disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    {isCreating ? 'Creating...' : 'Create sandbox'}
                  </button>
                </div>
                {/* Always-rendered slot sized for one line of error text, so
                    showing/hiding the message never shifts the OR divider or
                    Join section below it. The message itself stays conditional
                    so the field only exposes an error when there is one. */}
                <div className="mt-1 min-h-[1rem]">
                  {nameError && (
                    <p
                      id="sandbox-name-error"
                      data-testid="sandbox-name-error"
                      className="text-xs text-red-600"
                    >
                      {nameError}
                    </p>
                  )}
                </div>
              </form>
            </div>

            {/* Join an existing sandbox. The server returns only sandboxes that
                hold a clone of this workflow; hidden entirely when there are
                none. */}
            {(isLoadingList || sandboxes.length > 0) && (
              <div className="mt-6">
                <p
                  className="text-xs font-semibold uppercase tracking-wide
                    text-gray-500"
                >
                  Join an active sandbox
                </p>
                <p className="mt-1 text-xs text-gray-500">
                  Continue in a sandbox that's already active for this workflow.
                </p>

                {isLoadingList ? (
                  <SandboxListSkeleton />
                ) : (
                  // Cap the list at roughly 5-6 rows so a user with many
                  // sandboxes scrolls the list rather than the whole modal. The
                  // scroll container carries the row's -mx-3 bleed itself
                  // (-mx-3 px-3), so the rows fit exactly inside it: no
                  // horizontal scrollbar, the hover bleed is kept, and the px-3
                  // keeps the vertical scrollbar clear of the "Join" text.
                  <ul
                    className="mt-3 -mx-3 max-h-80 space-y-1 overflow-y-auto
                      overflow-x-hidden px-3"
                    data-testid="sandbox-list"
                  >
                    {sandboxes.map(sandbox => (
                      <SandboxRow
                        key={sandbox.id}
                        sandbox={sandbox}
                        onJoin={handleJoin}
                      />
                    ))}
                  </ul>
                )}
              </div>
            )}
          </DialogPanel>
        </div>
      </div>
    </Dialog>
  );
}
