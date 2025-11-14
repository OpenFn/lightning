import {
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
} from '@headlessui/react';
import { useEffect } from 'react';
import { useHotkeysContext } from 'react-hotkeys-hook';

import { HOTKEY_SCOPES } from '#/collaborative-editor/constants/hotkeys';

interface AlertDialogProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirm: () => void;
  title: string;
  description: string;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: 'danger' | 'primary';
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
}: AlertDialogProps) {
  const confirmButtonClass =
    variant === 'danger'
      ? 'bg-red-600 hover:bg-red-500 focus-visible:outline-red-600'
      : 'bg-primary-600 hover:bg-primary-500 focus-visible:outline-primary-600';

  // Use HotkeysContext to control keyboard scope precedence
  const { enableScope, disableScope } = useHotkeysContext();

  useEffect(() => {
    if (isOpen) {
      enableScope(HOTKEY_SCOPES.MODAL);
      disableScope(HOTKEY_SCOPES.PANEL);
      disableScope(HOTKEY_SCOPES.RUN_PANEL);
    } else {
      disableScope(HOTKEY_SCOPES.MODAL);
      enableScope(HOTKEY_SCOPES.PANEL);
    }

    return () => {
      disableScope(HOTKEY_SCOPES.MODAL);
    };
  }, [isOpen, enableScope, disableScope]);

  return (
    <Dialog open={isOpen} onClose={onClose} className="relative z-50">
      <DialogBackdrop
        transition
        className="fixed inset-0 bg-gray-500/75 transition-opacity
        data-closed:opacity-0 data-enter:duration-300 data-enter:ease-out
        data-leave:duration-200 data-leave:ease-in"
      />

      <div className="fixed inset-0 z-10 w-screen overflow-y-auto">
        <div
          className="flex min-h-full items-end justify-center p-4
        text-center sm:items-center sm:p-0"
        >
          <DialogPanel
            transition
            className="relative transform overflow-hidden rounded-lg
            bg-white px-4 pb-4 pt-5 text-left shadow-xl transition-all
            data-closed:translate-y-4 data-closed:opacity-0
            data-enter:duration-300 data-enter:ease-out
            data-leave:duration-200 data-leave:ease-in
            sm:my-8 sm:w-full sm:max-w-lg sm:p-6"
          >
            <div>
              <div className="mt-3 text-center sm:mt-5">
                <DialogTitle
                  as="h3"
                  className="text-base font-semibold text-gray-900"
                >
                  {title}
                </DialogTitle>
                <div className="mt-2">
                  <p className="text-sm text-gray-600">{description}</p>
                </div>
              </div>
            </div>
            <div
              className="mt-5 sm:mt-6 sm:grid sm:grid-flow-row-dense
            sm:grid-cols-2 sm:gap-3"
            >
              <button
                type="button"
                onClick={() => {
                  onConfirm();
                  onClose();
                }}
                className={`inline-flex w-full justify-center rounded-md
                px-3 py-2 text-sm font-semibold text-white shadow-xs
                focus-visible:outline-2 focus-visible:outline-offset-2
                sm:col-start-2 ${confirmButtonClass}`}
              >
                {confirmLabel}
              </button>
              <button
                type="button"
                onClick={onClose}
                className="mt-3 inline-flex w-full justify-center rounded-md
                bg-white px-3 py-2 text-sm font-semibold text-gray-900
                shadow-xs inset-ring inset-ring-gray-300
                hover:inset-ring-gray-400 sm:col-start-1 sm:mt-0"
              >
                {cancelLabel}
              </button>
            </div>
          </DialogPanel>
        </div>
      </div>
    </Dialog>
  );
}
