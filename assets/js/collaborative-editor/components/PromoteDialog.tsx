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
  /**
   * Whether this user may archive the sandbox. Gates the phase-two Archive
   * button: when false the success step only offers a close action and a note
   * that an admin can archive.
   */
  canArchiveSandbox: boolean;
  /**
   * Phase one. Save the current editor state, then merge it into the parent.
   * Resolves `true` to advance to the success step, `false` to stay on the
   * confirm step (the caller has already surfaced the error).
   */
  onConfirmPromote: () => Promise<boolean>;
  /**
   * Phase two. Archive the sandbox. Resolves `true` on success (the caller
   * navigates away, so this dialog is torn down), `false` to stay on the success
   * step so the user can retry or keep the sandbox.
   */
  onArchive: () => Promise<boolean>;
  /**
   * Phase two dismissal. Close and stay in the sandbox (no navigation), letting
   * the user switch to another workflow and promote it too.
   */
  onKeep: () => void;
  /** Phase one dismissal. Close without saving or promoting. */
  onCancel: () => void;
}

type Phase = 'confirm' | 'success';

/**
 * PromoteDialog - the two-phase "merge, then optionally archive" flow.
 *
 * Phase one confirms the save-and-merge into the parent project. On success the
 * dialog transforms in place into a success step (phase two) that offers an
 * optional archive, mirroring GitHub's "merge, then delete the branch". Because
 * this is multi-phase and carries its own in-flight states, it is a dedicated
 * component rather than the generic AlertDialog.
 *
 * Navigation lives in the caller: keeping the sandbox stays put (caller shows a
 * toast), archiving hard-navigates into the parent project.
 */
export function PromoteDialog({
  isOpen,
  canArchiveSandbox,
  onConfirmPromote,
  onArchive,
  onKeep,
  onCancel,
}: PromoteDialogProps) {
  const [phase, setPhase] = useState<Phase>('confirm');
  const [isPromoting, setIsPromoting] = useState(false);
  const [isArchiving, setIsArchiving] = useState(false);

  const isBusy = isPromoting || isArchiving;

  // Reset to the confirm step each time the dialog is (re)opened so a second
  // promote never starts on the previous run's success step.
  useEffect(() => {
    if (isOpen) {
      setPhase('confirm');
      setIsPromoting(false);
      setIsArchiving(false);
    }
  }, [isOpen]);

  // Dismissing means different things per phase: cancel on confirm, keep on
  // success. Never dismiss mid-flight so a save/merge/archive can't be orphaned.
  const handleDismiss = () => {
    if (isBusy) return;
    if (phase === 'success') {
      onKeep();
    } else {
      onCancel();
    }
  };

  // High-priority Escape handler, matching AlertDialog, so the dialog closes
  // before the IDE/inspector Escape handlers can fire.
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
    // On success the caller hard-navigates, tearing this down; only reset the
    // in-flight flag when it failed so the buttons become interactive again.
    if (!ok) {
      setIsArchiving(false);
    }
  };

  return (
    <Dialog
      open={isOpen}
      onClose={handleDismiss}
      className="relative z-[60]"
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
