// Modal from a live workflow: create a new sandbox or join an active one; both hard-navigate to the sandbox editor.

import {
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
} from '@headlessui/react';
import { format } from 'date-fns';
import { useCallback, useEffect, useState } from 'react';

import { useWorkflowActions } from '../hooks/useWorkflow';
import {
  formatChannelErrorMessage,
  isChannelRequestError,
} from '../lib/errors';
import { notifications } from '../lib/notifications';
import type { Sandbox, SandboxCollaborator } from '../types/workflow';

interface EditInSandboxPickerProps {
  isOpen: boolean;
  onClose: () => void;
}

function personInitials(person: SandboxCollaborator): string {
  const source = person.name?.trim() || person.email?.trim() || '';
  if (!source) return '?';

  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length >= 2 && parts[0] && parts[1]) {
    return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
  }
  return source.slice(0, 2).toUpperCase();
}

// A joinable sandbox row: creator avatar on the left, then the sandbox name over
// a single muted metadata line ("Created {date}, {time} · {creator}"), and the
// Join button on the right. The creator can be null (unknown), in which case the
// avatar and the "· {creator}" suffix are omitted.
function SandboxRow({
  sandbox,
  onJoin,
}: {
  sandbox: Sandbox;
  onJoin: (sandbox: Sandbox) => void;
}) {
  const { creator } = sandbox;
  const creatorName = creator ? creator.name || creator.email || '' : '';
  const created = formatCreatedAt(sandbox.inserted_at);

  return (
    <li
      className="flex items-center justify-between gap-4 px-4 py-3"
      data-testid="sandbox-row"
    >
      <div className="flex min-w-0 items-center gap-3">
        {creator && (
          <span
            title={creatorName || undefined}
            className="inline-flex h-8 w-8 shrink-0 items-center justify-center
              rounded-full bg-gray-200 text-xs font-medium text-gray-700"
          >
            {personInitials(creator)}
          </span>
        )}
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold text-gray-900">
            {sandbox.name}
          </p>
          {/* The date never truncates; only the creator name gives way when
              space is tight. */}
          <p className="flex min-w-0 items-center gap-1 text-xs text-gray-500">
            <span className="shrink-0 whitespace-nowrap">{created}</span>
            {creator && creatorName && (
              <>
                <span aria-hidden="true" className="shrink-0">
                  ·
                </span>
                <span className="min-w-0 truncate">{creatorName}</span>
              </>
            )}
          </p>
        </div>
      </div>
      <button
        type="button"
        data-testid="join-sandbox-button"
        onClick={() => {
          onJoin(sandbox);
        }}
        className="inline-flex shrink-0 items-center rounded-md px-3 py-1.5
          text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset
          ring-gray-300 hover:bg-gray-50"
      >
        Join
      </button>
    </li>
  );
}

function formatCreatedAt(insertedAt: string): string {
  const date = new Date(insertedAt);
  if (Number.isNaN(date.getTime())) return '';
  return `Created ${format(date, 'd MMM yyyy, HH:mm')}`;
}

const navigateToSandbox = (projectId: string, workflowId: string) => {
  window.location.href = `/projects/${projectId}/w/${workflowId}`;
};

export function EditInSandboxPicker({
  isOpen,
  onClose,
}: EditInSandboxPickerProps) {
  const { listSandboxes, editInSandbox } = useWorkflowActions();

  const [name, setName] = useState('');
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
          const description = isChannelRequestError(error)
            ? formatChannelErrorMessage({
                errors: error.errors as { base?: string[] } & Record<
                  string,
                  string[]
                >,
                type: error.type,
              })
            : 'Please try again.';
          notifications.alert({
            title: 'Could not load sandboxes',
            description,
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
    const trimmed = name.trim();

    const create = async () => {
      try {
        const { project_id, workflow_id } = await editInSandbox(trimmed);
        navigateToSandbox(project_id, workflow_id);
      } catch (error) {
        const description = isChannelRequestError(error)
          ? formatChannelErrorMessage({
              errors: error.errors as { base?: string[] } & Record<
                string,
                string[]
              >,
              type: error.type,
            })
          : 'Please try again.';
        notifications.alert({
          title: 'Could not create a sandbox',
          description,
        });
        setIsCreating(false);
      }
    };

    void create();
  }, [name, editInSandbox]);

  const handleJoin = useCallback((sandbox: Sandbox) => {
    if (!sandbox.workflow_id) return;
    navigateToSandbox(sandbox.id, sandbox.workflow_id);
  }, []);

  // A name is required to create. A sandbox is only worth listing when it
  // contains a clone of this workflow; the rest can't edit it, so drop them.
  const canCreate = name.trim().length > 0;
  const joinableSandboxes = sandboxes.filter(
    sandbox => sandbox.workflow_id !== null
  );

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

            {/* Create a new sandbox */}
            <div className="mt-4 rounded-md border border-gray-200 p-4">
              <label
                htmlFor="sandbox-name"
                className="block text-sm font-medium text-gray-900"
              >
                Create a new sandbox
              </label>
              <p className="mt-1 text-sm text-gray-600">
                Branches from the current live version.
              </p>
              <div className="mt-3 flex gap-2">
                <input
                  id="sandbox-name"
                  type="text"
                  value={name}
                  onChange={event => {
                    setName(event.target.value);
                  }}
                  placeholder="Sandbox name"
                  disabled={isCreating}
                  className="block w-full rounded-md border-0 px-3 py-2 text-sm
                    text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300
                    placeholder:text-gray-400 focus:ring-2 focus:ring-inset
                    focus:ring-primary-600 disabled:cursor-not-allowed
                    disabled:opacity-50"
                />
                <button
                  type="button"
                  data-testid="create-sandbox-button"
                  onClick={handleCreate}
                  disabled={isCreating || !canCreate}
                  className="inline-flex shrink-0 items-center gap-1 rounded-md
                    bg-primary-600 px-3 py-2 text-sm font-semibold text-white
                    shadow-sm hover:bg-primary-500 disabled:cursor-not-allowed
                    disabled:opacity-50"
                >
                  <span className="hero-beaker h-4 w-4" />
                  {isCreating ? 'Creating...' : 'Create sandbox'}
                </button>
              </div>
            </div>

            {/* Join an existing sandbox. Only sandboxes that hold a clone of
                this workflow are listed; hidden entirely when there are none. */}
            {(isLoadingList || joinableSandboxes.length > 0) && (
              <div className="mt-4">
                <h4 className="text-sm font-medium text-gray-900">
                  Join an active sandbox
                </h4>

                {isLoadingList ? (
                  <p
                    className="mt-2 text-sm text-gray-500"
                    data-testid="sandbox-list-loading"
                  >
                    Loading sandboxes...
                  </p>
                ) : (
                  <ul
                    className="mt-2 divide-y divide-gray-100 rounded-md border
                      border-gray-200"
                    data-testid="sandbox-list"
                  >
                    {joinableSandboxes.map(sandbox => (
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

            <div className="mt-5 flex justify-end">
              <button
                type="button"
                onClick={onClose}
                disabled={isCreating}
                className="inline-flex justify-center rounded-md bg-white px-3
                  py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1
                  ring-inset ring-gray-300 hover:bg-gray-50
                  disabled:cursor-not-allowed disabled:opacity-50"
              >
                Cancel
              </button>
            </div>
          </DialogPanel>
        </div>
      </div>
    </Dialog>
  );
}
