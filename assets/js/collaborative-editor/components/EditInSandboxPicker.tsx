/**
 * # Edit in sandbox picker
 *
 * Modal shown from a live workflow on a non-sandbox project. It offers two
 * ways to start editing in a sandbox:
 *
 * 1. Create a new sandbox branched from the current live version.
 * 2. Join an existing active sandbox.
 *
 * A sandbox is a separate project, so both paths hard-navigate to the sandbox
 * project's editor (a new project means a new Y.Doc session), consistent with
 * the legacy-editor switch. The list is fetched when the dialog opens and is
 * rendered in the order returned by the server (last-edited first).
 */

import {
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
} from '@headlessui/react';
import { formatDistanceToNow } from 'date-fns';
import { useCallback, useEffect, useState } from 'react';
import { toast } from 'sonner';

import { cn } from '../../utils/cn';
import { useWorkflowActions } from '../hooks/useWorkflow';
import { ChannelRequestError } from '../lib/errors';
import type { Sandbox, SandboxCollaborator } from '../types/workflow';

interface EditInSandboxPickerProps {
  isOpen: boolean;
  onClose: () => void;
}

/**
 * The server returns a human-readable reason in `errors.base` (a usage-limit
 * upsell, a permission message, etc.). Surface it rather than a generic toast.
 */
function serverMessage(error: unknown): string | null {
  if (error instanceof ChannelRequestError) {
    return error.errors['base']?.[0] ?? null;
  }
  return null;
}

function collaboratorInitials(collaborator: SandboxCollaborator): string {
  const source = collaborator.name?.trim() || collaborator.email?.trim() || '';
  if (!source) return '?';

  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length >= 2 && parts[0] && parts[1]) {
    return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
  }
  return source.slice(0, 2).toUpperCase();
}

function CollaboratorAvatars({
  collaborators,
}: {
  collaborators: SandboxCollaborator[];
}) {
  if (collaborators.length === 0) return null;

  const visible = collaborators.slice(0, 4);
  const overflow = collaborators.length - visible.length;

  return (
    <div className="flex items-center -space-x-1.5">
      {visible.map(collaborator => (
        <span
          key={collaborator.id}
          title={collaborator.name || collaborator.email || undefined}
          className="inline-flex h-6 w-6 items-center justify-center rounded-full
            bg-gray-200 text-[10px] font-medium text-gray-700 ring-2 ring-white"
        >
          {collaboratorInitials(collaborator)}
        </span>
      ))}
      {overflow > 0 && (
        <span
          className="inline-flex h-6 w-6 items-center justify-center rounded-full
            bg-gray-100 text-[10px] font-medium text-gray-500 ring-2 ring-white"
        >
          +{overflow}
        </span>
      )}
    </div>
  );
}

function formatUpdatedAt(updatedAt: string): string {
  const date = new Date(updatedAt);
  if (Number.isNaN(date.getTime())) return '';
  return `edited ${formatDistanceToNow(date, { addSuffix: true })}`;
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
          toast.error(
            serverMessage(error) ??
              'Could not load sandboxes. Please try again.'
          );
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
        const { project_id, workflow_id } = await editInSandbox(
          trimmed || undefined
        );
        navigateToSandbox(project_id, workflow_id);
      } catch (error) {
        toast.error(
          serverMessage(error) ??
            'Could not create a sandbox. Please try again.'
        );
        setIsCreating(false);
      }
    };

    void create();
  }, [name, editInSandbox]);

  const handleJoin = useCallback((sandbox: Sandbox) => {
    if (!sandbox.workflow_id) return;
    navigateToSandbox(sandbox.id, sandbox.workflow_id);
  }, []);

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
                  placeholder="Sandbox name (optional)"
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
                  disabled={isCreating}
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

            {/* Join an existing sandbox */}
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
              ) : sandboxes.length === 0 ? (
                <p
                  className="mt-2 text-sm text-gray-500"
                  data-testid="sandbox-list-empty"
                >
                  No active sandboxes yet.
                </p>
              ) : (
                <ul
                  className="mt-2 divide-y divide-gray-100 rounded-md border
                    border-gray-200"
                  data-testid="sandbox-list"
                >
                  {sandboxes.map(sandbox => {
                    const canJoin = sandbox.workflow_id !== null;
                    return (
                      <li
                        key={sandbox.id}
                        className="flex items-center justify-between gap-3 px-3
                          py-2.5"
                        data-testid="sandbox-row"
                      >
                        <div className="min-w-0">
                          <p className="truncate text-sm font-medium text-gray-900">
                            {sandbox.name}
                          </p>
                          <p className="text-xs text-gray-500">
                            {formatUpdatedAt(sandbox.updated_at)}
                          </p>
                        </div>
                        <div className="flex shrink-0 items-center gap-3">
                          <CollaboratorAvatars
                            collaborators={sandbox.collaborators}
                          />
                          <button
                            type="button"
                            data-testid="join-sandbox-button"
                            onClick={() => {
                              handleJoin(sandbox);
                            }}
                            disabled={!canJoin}
                            title={
                              canJoin
                                ? undefined
                                : "This workflow isn't in that sandbox"
                            }
                            className={cn(
                              'inline-flex items-center rounded-md px-3 py-1.5',
                              'text-sm font-semibold shadow-sm',
                              canJoin
                                ? 'bg-white text-gray-900 ring-1 ring-inset ring-gray-300 hover:bg-gray-50'
                                : 'cursor-not-allowed bg-white text-gray-400 ring-1 ring-inset ring-gray-200'
                            )}
                          >
                            Join
                          </button>
                        </div>
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>

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
