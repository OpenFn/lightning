import {
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
} from '@headlessui/react';
import { useEffect, useState } from 'react';

import { useKeyboardShortcut } from '../keyboard';

import { Button } from './Button';

export interface LosingTrigger {
  id: string;
  type: string;
  custom_path: string | null;
  enabled: boolean;
}

export interface ReturningTrigger {
  id: string;
  type: string;
  custom_path: string | null;
}

export interface RestoreCost {
  losing: LosingTrigger[];
  returning: ReturningTrigger[];
}

interface RestoreVersionDialogProps {
  isOpen: boolean;
  versionNumber: number | null;
  /** Null while the answer is still coming back. */
  cost: RestoreCost | null;
  onConfirm: () => Promise<boolean>;
  onCancel: () => void;
}

function describeTrigger(trigger: LosingTrigger | ReturningTrigger) {
  if (trigger.type === 'cron') return 'a scheduled trigger';

  return trigger.custom_path
    ? `the webhook at /${trigger.custom_path}`
    : 'a webhook trigger';
}

/**
 * Asked before an earlier version's content replaces what is live.
 *
 * Restoring is not a mistake to be warned about, it is a deliberate rollback,
 * so this says what it costs rather than trying to talk anyone out of it. The
 * costs worth naming are the ones nobody should discover afterwards: a trigger
 * added since that version disappears, and the URL built from it stops
 * answering.
 */
export function RestoreVersionDialog({
  isOpen,
  versionNumber,
  cost,
  onConfirm,
  onCancel,
}: RestoreVersionDialogProps) {
  const [isRestoring, setIsRestoring] = useState(false);

  // Nothing unmounts this between opens, so it has to clear its own in-flight
  // state or the next open is a dead button.
  useEffect(() => {
    if (!isOpen) setIsRestoring(false);
  }, [isOpen]);

  const dismiss = () => {
    if (isRestoring) return;
    onCancel();
  };

  useKeyboardShortcut('Escape', dismiss, 100, { enabled: isOpen });

  const handleConfirm = async () => {
    setIsRestoring(true);

    const restored = await onConfirm();

    if (!restored) setIsRestoring(false);
  };

  const isChecking = cost === null;

  return (
    <Dialog open={isOpen} onClose={dismiss} className="relative z-[60]">
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
            data-testid="restore-version-dialog"
          >
            <DialogTitle
              as="h3"
              className="text-base font-semibold text-gray-900"
            >
              Restore v{versionNumber}?
            </DialogTitle>

            <p className="mt-2 text-sm text-gray-600">
              This puts v{versionNumber}&rsquo;s content back and publishes it.
              The workflow stays live throughout, and anything it has gained
              since v{versionNumber} is lost. The versions in between stay in
              the history.
            </p>

            {isChecking ? (
              <p
                className="mt-3 text-sm text-gray-500"
                data-testid="restore-checking"
              >
                Checking what this will change...
              </p>
            ) : (
              <>
                {cost.losing.length > 0 && (
                  <div
                    className="mt-3 rounded-md bg-danger-50 p-3"
                    data-testid="restore-losing-triggers"
                  >
                    <p className="text-sm font-medium text-danger-800">
                      {cost.losing.length === 1
                        ? 'One trigger will be deleted'
                        : `${cost.losing.length} triggers will be deleted`}
                    </p>
                    <ul className="mt-1 list-disc pl-5 text-sm text-danger-700">
                      {cost.losing.map(trigger => (
                        <li key={trigger.id}>
                          {describeTrigger(trigger)}
                          {trigger.enabled ? ', which is on now' : ''}
                        </li>
                      ))}
                    </ul>
                    <p className="mt-1 text-sm text-danger-700">
                      Anything calling those URLs stops working.
                    </p>
                  </div>
                )}

                {cost.returning.length > 0 && (
                  <div
                    className="mt-3 rounded-md bg-warning-50 p-3"
                    data-testid="restore-returning-triggers"
                  >
                    <p className="text-sm font-medium text-warning-800">
                      {cost.returning.length === 1
                        ? 'One trigger comes back switched off'
                        : `${cost.returning.length} triggers come back switched off`}
                    </p>
                    <ul className="mt-1 list-disc pl-5 text-sm text-warning-700">
                      {cost.returning.map(trigger => (
                        <li key={trigger.id}>{describeTrigger(trigger)}</li>
                      ))}
                    </ul>
                    <p className="mt-1 text-sm text-warning-700">
                      A version does not record which authentication was
                      attached, so switch these on again once you have set that
                      up.
                    </p>
                  </div>
                )}
              </>
            )}

            <div className="mt-6 flex flex-wrap justify-end gap-3">
              <Button
                variant="secondary"
                disabled={isRestoring}
                onClick={onCancel}
              >
                Cancel
              </Button>
              <Button
                variant="danger"
                loading={isRestoring}
                disabled={isChecking}
                onClick={() => void handleConfirm()}
              >
                {isRestoring ? 'Restoring...' : `Restore v${versionNumber}`}
              </Button>
            </div>
          </DialogPanel>
        </div>
      </div>
    </Dialog>
  );
}
