import {
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
} from '@headlessui/react';
import type React from 'react';

import { useKeyboardShortcut } from '../keyboard';

import { Button } from './Button';

interface AlertDialogProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirm: () => void;
  title: string;
  description: string;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: 'danger' | 'primary';
  /**
   * Optional extra content rendered below the description (e.g. a
   * "don't show again" checkbox). Left-aligned so form controls read naturally.
   */
  children?: React.ReactNode;
}

/**
 * AlertDialog - Reusable confirmation dialog component
 *
 * Uses Headless UI Dialog primitives with transitions and proper
 * accessibility. Follows the Menu component pattern from Header.tsx.
 *
 * @example
 * <AlertDialog
 *   isOpen={isDialogOpen}
 *   onClose={() => setIsDialogOpen(false)}
 *   onConfirm={handleDangerousAction}
 *   title="Delete Item?"
 *   description="This action cannot be undone."
 *   confirmLabel="Delete"
 *   variant="danger"
 * />
 */
export function AlertDialog({
  isOpen,
  onClose,
  onConfirm,
  title,
  description,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  variant = 'primary',
  children,
}: AlertDialogProps) {
  // High-priority Escape handler to prevent closing the parent IDE/inspector.
  // Priority 100 (MODAL) ensures this runs before the IDE handler (priority 50);
  // Headless UI's own Escape handling never fires while those intercept it. Only
  // cancels (onClose) the dialog, so it never triggers the confirm action.
  useKeyboardShortcut(
    'Escape',
    () => {
      onClose();
    },
    100,
    { enabled: isOpen }
  );

  return (
    <Dialog open={isOpen} onClose={onClose} className="relative z-[60]">
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
            <DialogTitle
              as="h3"
              className="text-base font-semibold text-gray-900"
            >
              {title}
            </DialogTitle>
            <p className="mt-2 text-sm text-gray-600">{description}</p>

            {children != null && <div className="mt-4">{children}</div>}

            <div className="mt-6 flex justify-end gap-3">
              <Button variant="secondary" onClick={onClose}>
                {cancelLabel}
              </Button>
              <Button
                variant={variant}
                onClick={() => {
                  onConfirm();
                  onClose();
                }}
              >
                {confirmLabel}
              </Button>
            </div>
          </DialogPanel>
        </div>
      </div>
    </Dialog>
  );
}
