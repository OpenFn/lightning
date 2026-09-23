/** Confirms a promote back into the parent project, then offers to archive. */

import {
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
} from '@headlessui/react';
import { useEffect, useState } from 'react';

import { useKeyboardShortcut } from '../keyboard';

import { Button } from './Button';

interface PromoteDialogProps {
  isOpen: boolean;
  canArchiveSandbox: boolean;
  onConfirmPromote: () => Promise<boolean>;
  onArchive: () => Promise<boolean>;
  onKeep: () => void;
  onCancel: () => void;
  onCheckDivergence: () => Promise<{
    diverged: boolean;
    parent_name: string | null;
  }>;
}

type Phase = 'confirm' | 'success';

export function PromoteDialog({
  isOpen,
  canArchiveSandbox,
  onConfirmPromote,
  onArchive,
  onKeep,
  onCancel,
  onCheckDivergence,
}: PromoteDialogProps) {
  const [phase, setPhase] = useState<Phase>('confirm');
  const [isPromoting, setIsPromoting] = useState(false);
  const [isArchiving, setIsArchiving] = useState(false);
  const [divergedParentName, setDivergedParentName] = useState<string | null>(
    null
  );
  const [checkFailed, setCheckFailed] = useState(false);
  const [checking, setChecking] = useState(true);
  const [wasOpen, setWasOpen] = useState(isOpen);

  const isBusy = isPromoting || isArchiving;

  if (isOpen !== wasOpen) {
    setWasOpen(isOpen);

    if (isOpen) {
      setPhase('confirm');
      setIsPromoting(false);
      setIsArchiving(false);
      setDivergedParentName(null);
      setCheckFailed(false);
      setChecking(true);
    }
  }

  useEffect(() => {
    if (!isOpen) return;

    let cancelled = false;

    void onCheckDivergence()
      .then(({ diverged, parent_name }) => {
        if (!cancelled && diverged && parent_name) {
          setDivergedParentName(parent_name);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setCheckFailed(true);
        }
      })
      .finally(() => {
        if (!cancelled) {
          setChecking(false);
        }
      });

    return () => {
      cancelled = true;
    };
  }, [isOpen, onCheckDivergence]);

  const handleDismiss = () => {
    if (isBusy) return;
    if (phase === 'success') {
      onKeep();
    } else {
      onCancel();
    }
  };

  useKeyboardShortcut(
    'Escape',
    () => {
      handleDismiss();
    },
    100,
    { enabled: isOpen }
  );

  const handleConfirm = async () => {
    setIsPromoting(true);
    const ok = await onConfirmPromote();
    setIsPromoting(false);
    if (ok) {
      setPhase('success');
    }
  };

  const handleArchive = async () => {
    setIsArchiving(true);
    const ok = await onArchive();
    if (!ok) {
      setIsArchiving(false);
    }
  };

  return (
    <Dialog open={isOpen} onClose={handleDismiss} className="relative z-[60]">
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
              sm:max-w-md sm:p-6"
          >
            {phase === 'confirm' ? (
              <>
                <DialogTitle
                  as="h3"
                  className="text-base font-semibold text-gray-900"
                >
                  Save and promote to parent project
                </DialogTitle>
                <p className="mt-2 text-sm text-gray-600">
                  Your current changes in this sandbox are saved, then merged
                  into the parent project's live workflow. The parent stays live
                  and starts processing data with these changes.
                </p>

                {checking && (
                  <p className="mt-4 text-sm text-gray-500">
                    Checking whether the parent has changed since this sandbox
                    was created...
                  </p>
                )}

                {checkFailed && (
                  <p className="mt-4 text-sm text-gray-500">
                    We could not check whether the parent has changed since this
                    sandbox was created.
                  </p>
                )}

                {divergedParentName !== null && (
                  <div
                    className="mt-4 flex gap-2.5 rounded-md bg-amber-50 p-3
                      text-sm text-amber-800"
                  >
                    <span
                      className="hero-exclamation-triangle mt-0.5 h-4 w-4
                        shrink-0 text-amber-500"
                      aria-hidden="true"
                    />
                    <p>
                      This workflow has changed in{' '}
                      <span className="font-semibold">
                        {divergedParentName}
                      </span>{' '}
                      since this sandbox was created. Promoting replaces that
                      version with yours, and anything added there is removed.
                    </p>
                  </div>
                )}

                <div className="mt-6 flex justify-end gap-3">
                  <Button
                    variant="secondary"
                    disabled={isBusy}
                    onClick={onCancel}
                  >
                    Cancel
                  </Button>
                  <Button
                    variant="primary"
                    loading={isPromoting}
                    disabled={checking}
                    onClick={() => void handleConfirm()}
                  >
                    {isPromoting ? (
                      <span className="inline-flex items-center gap-1">
                        <span
                          className="hero-arrow-path h-4 w-4 animate-spin"
                          aria-hidden="true"
                        />
                        Promoting...
                      </span>
                    ) : (
                      'Save and promote'
                    )}
                  </Button>
                </div>
              </>
            ) : (
              <>
                <div className="flex items-center gap-2.5">
                  <span
                    className="flex size-6 shrink-0 items-center justify-center
                      rounded-full bg-green-100"
                  >
                    <span
                      className="hero-check-micro h-4 w-4 text-green-600"
                      aria-hidden="true"
                    />
                  </span>
                  <DialogTitle
                    as="h3"
                    className="text-base font-semibold text-gray-900"
                  >
                    Changes promoted
                  </DialogTitle>
                </div>
                <p className="mt-2 text-sm text-gray-600">
                  Your changes are now live in the parent project.
                </p>

                <div className="mt-5 border-t border-gray-200 pt-5">
                  <p className="text-sm font-semibold text-gray-900">
                    Archive this sandbox?
                  </p>
                  <p className="mt-1 text-sm text-gray-600">
                    Archiving turns off its triggers and schedules it for
                    deletion. Keep it if you want to promote more workflows from
                    it first.
                  </p>
                  {!canArchiveSandbox && (
                    <p className="mt-2 text-sm text-gray-500">
                      Ask an admin to archive this sandbox.
                    </p>
                  )}
                </div>

                <div className="mt-6 flex justify-end gap-3">
                  {canArchiveSandbox ? (
                    <>
                      <Button
                        variant="secondary"
                        disabled={isArchiving}
                        onClick={onKeep}
                      >
                        Keep sandbox
                      </Button>
                      <Button
                        variant="primary"
                        loading={isArchiving}
                        onClick={() => void handleArchive()}
                      >
                        {isArchiving ? (
                          <span className="inline-flex items-center gap-1">
                            <span
                              className="hero-arrow-path h-4 w-4 animate-spin"
                              aria-hidden="true"
                            />
                            Archiving...
                          </span>
                        ) : (
                          'Archive sandbox'
                        )}
                      </Button>
                    </>
                  ) : (
                    <Button variant="primary" onClick={onKeep}>
                      Done
                    </Button>
                  )}
                </div>
              </>
            )}
          </DialogPanel>
        </div>
      </div>
    </Dialog>
  );
}
