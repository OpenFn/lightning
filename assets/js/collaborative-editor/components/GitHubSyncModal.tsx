import {
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
} from "@headlessui/react";
import { useEffect, useState } from "react";
import { useHotkeysContext } from "react-hotkeys-hook";

import { useIsGitHubSyncModalOpen, useUICommands } from "../hooks/useUI";
import { useWorkflowActions } from "../hooks/useWorkflow";

/**
 * GitHubSyncModal - Modal for saving workflow and syncing to GitHub
 *
 * Uses Headless UI Dialog primitives with transitions and proper
 * accessibility. Follows the AlertDialog pattern.
 *
 * Features:
 * - Textarea for commit message input
 * - Save & Sync button that triggers workflow save and GitHub sync
 * - Cancel button to close without syncing
 * - Proper keyboard scope management
 *
 * @example
 * // Add to WorkflowEditor or Header component
 * <GitHubSyncModal />
 */
export function GitHubSyncModal() {
  const isOpen = useIsGitHubSyncModalOpen();
  const { closeGitHubSyncModal } = useUICommands();
  const { saveAndSyncWorkflow } = useWorkflowActions();

  const [commitMessage, setCommitMessage] = useState("");
  const [isSaving, setIsSaving] = useState(false);

  // Use HotkeysContext to control keyboard scope precedence
  const { enableScope, disableScope } = useHotkeysContext();

  // When modal opens, take control by disabling panel scope
  // When modal closes, give control back by re-enabling panel scope
  useEffect(() => {
    if (isOpen) {
      enableScope("modal");
      disableScope("panel");
    } else {
      disableScope("modal");
      enableScope("panel");
    }

    // Cleanup: ensure modal scope is disabled when unmounted
    return () => {
      disableScope("modal");
    };
  }, [isOpen, enableScope, disableScope]);

  // Reset commit message when modal opens
  useEffect(() => {
    if (isOpen) {
      setCommitMessage("");
    }
  }, [isOpen]);

  const handleSaveAndSync = async () => {
    if (!commitMessage.trim()) {
      return;
    }

    setIsSaving(true);
    try {
      await saveAndSyncWorkflow(commitMessage.trim());
      closeGitHubSyncModal();
    } catch (error) {
      // Error is already handled by useWorkflowActions with toast notification
      console.error("Failed to save and sync:", error);
    } finally {
      setIsSaving(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      void handleSaveAndSync();
    }
  };

  return (
    <Dialog
      open={isOpen}
      onClose={closeGitHubSyncModal}
      className="relative z-50"
    >
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
                  Save and sync changes to GitHub
                </DialogTitle>
                <div className="mt-4">
                  <label
                    htmlFor="commit-message"
                    className="block text-left text-sm font-medium text-gray-700 mb-2"
                  >
                    Commit message
                  </label>
                  <textarea
                    id="commit-message"
                    rows={4}
                    className="block w-full rounded-md border-gray-300 shadow-xs
                    focus:border-primary-500 focus:ring-primary-500 sm:text-sm"
                    placeholder="Describe your changes..."
                    value={commitMessage}
                    onChange={e => setCommitMessage(e.target.value)}
                    onKeyDown={handleKeyDown}
                    autoFocus
                  />
                  <p className="mt-2 text-xs text-gray-500 text-left">
                    Tip: Press Ctrl+Enter (or Cmd+Enter) to save and sync
                  </p>
                </div>
              </div>
            </div>
            <div
              className="mt-5 sm:mt-6 sm:grid sm:grid-flow-row-dense
            sm:grid-cols-2 sm:gap-3"
            >
              <button
                type="button"
                onClick={handleSaveAndSync}
                disabled={!commitMessage.trim() || isSaving}
                className="inline-flex w-full justify-center rounded-md
                px-3 py-2 text-sm font-semibold text-white shadow-xs
                bg-primary-600 hover:bg-primary-500
                disabled:opacity-50 disabled:cursor-not-allowed
                focus-visible:outline-2 focus-visible:outline-offset-2
                focus-visible:outline-primary-600
                sm:col-start-2"
              >
                {isSaving ? "Saving..." : "Save & Sync"}
              </button>
              <button
                type="button"
                onClick={closeGitHubSyncModal}
                disabled={isSaving}
                className="mt-3 inline-flex w-full justify-center rounded-md
                bg-white px-3 py-2 text-sm font-semibold text-gray-900
                shadow-xs inset-ring inset-ring-gray-300
                hover:inset-ring-gray-400
                disabled:opacity-50 disabled:cursor-not-allowed
                sm:col-start-1 sm:mt-0"
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
