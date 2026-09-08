import {
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
} from '@headlessui/react';
import { useState } from 'react';

import { useKeyboardShortcut } from '../keyboard';

import { Button } from './Button';

interface DiscardChangesDialogProps {
  isOpen: boolean;
  /** Save, then continue only if the save succeeded. Resolves false on failure. */
  onSaveAndContinue: () => Promise<boolean>;
  /** Continue and let the unsaved edits go. */
  onDiscardAndContinue: () => void;
  onCancel: () => void;
  /** What the person is about to do, if it is not switching version. */
  description?: string;
}

/**
 * Asked before something throws away unsaved edits.
 *
 * Three ways out rather than two: saving is usually what the person wanted, and
 * making them cancel, save, then repeat the action is a poor exchange for an
 * interruption we caused.
 */
export function DiscardChangesDialog({
  isOpen,
  onSaveAndContinue,
  onDiscardAndContinue,
  onCancel,
  description = 'Switching loads a different version of this workflow, and your unsaved changes cannot come with it. Switch without saving and they are gone.',
}: DiscardChangesDialogProps) {
  const [isSaving, setIsSaving] = useState(false);

  const dismiss = () => {
    if (isSaving) return;
    onCancel();
  };

  useKeyboardShortcut('Escape', dismiss, 100, { enabled: isOpen });

  const handleSave = async () => {
    setIsSaving(true);

    const saved = await onSaveAndContinue();

    // On success the caller navigates and tears this down; only recover the
    // button when the save failed.
    if (!saved) setIsSaving(false);
  };

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
              sm:max-w-md sm:p-6"
            data-testid="discard-changes-dialog"
          >
            <DialogTitle
              as="h3"
              className="text-base font-semibold text-gray-900"
            >
              You have unsaved changes
            </DialogTitle>
            <p className="mt-2 text-sm text-gray-600">{description}</p>

            <div className="mt-6 flex flex-wrap justify-end gap-3">
              <Button
                variant="secondary"
                disabled={isSaving}
                onClick={onCancel}
              >
                Cancel
              </Button>
              <Button
                variant="secondary"
                disabled={isSaving}
                onClick={onDiscardAndContinue}
              >
                Switch
              </Button>
              <Button loading={isSaving} onClick={() => void handleSave()}>
                {isSaving ? 'Saving...' : 'Save and switch'}
              </Button>
            </div>
          </DialogPanel>
        </div>
      </div>
    </Dialog>
  );
}
