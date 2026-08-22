import { useCallback, useRef, useState } from 'react';

import type { Workflow } from '#/collaborative-editor/types/workflow';

interface UseAdaptorChangeConfirmationProps {
  job: Workflow.Job | null;
  updateJob: (jobId: string, updates: Partial<Workflow.Job>) => void;
  setIsAdaptorPickerOpen: (open: boolean) => void;
  setIsConfigureModalOpen: (open: boolean) => void;
  onAdaptorChangeStart?: () => void; // Optional callback before change (for form sync)
}

interface UseAdaptorChangeConfirmationReturn {
  // Modal state
  isAdaptorChangeConfirmationOpen: boolean;

  // Handler to call when user selects adaptor from list
  handleAdaptorSelect: (adaptorName: string) => void;

  // Handler for confirmation button
  handleConfirmAdaptorChange: () => void;

  // Handler for cancel button (navigates back to adaptor list)
  handleCancelAdaptorChange: () => void;

  // Handler for modal close/ESC (cleanup only, no navigation)
  handleCloseConfirmation: () => void;
}

/**
 * Custom hook for handling adaptor changes with credential reset confirmation.
 *
 * When a user selects a different adaptor:
 * - If job has credentials → shows confirmation modal
 * - If no credentials → proceeds immediately
 * - On confirm → changes adaptor AND resets credentials
 * - On cancel → returns to adaptor selection modal
 *
 * @example
 * const { handleAdaptorSelect, ... } = useAdaptorChangeConfirmation({
 *   job: currentJob,
 *   updateJob,
 *   setIsAdaptorPickerOpen,
 *   setIsConfigureModalOpen,
 * });
 */
export function useAdaptorChangeConfirmation({
  job,
  updateJob,
  setIsAdaptorPickerOpen,
  setIsConfigureModalOpen,
  onAdaptorChangeStart,
}: UseAdaptorChangeConfirmationProps): UseAdaptorChangeConfirmationReturn {
  const [isAdaptorChangeConfirmationOpen, setIsAdaptorChangeConfirmationOpen] =
    useState(false);
  const [pendingAdaptorSelection, setPendingAdaptorSelection] = useState<
    string | null
  >(null);

  // Track if we're confirming (not canceling) to handle AlertDialog's dual onClose call
  const isConfirmingRef = useRef(false);

  const handleAdaptorSelect = useCallback(
    (adaptorName: string) => {
      if (!job) return;

      // Extract package name from selected adaptor (e.g., "@openfn/language-chatgpt" from "@openfn/language-chatgpt@1.0.0")
      const selectedPackageMatch = adaptorName.match(/(.+?)(@|$)/);
      const selectedPackage = selectedPackageMatch
        ? selectedPackageMatch[1]
        : adaptorName;

      // Extract package name from current adaptor
      const currentAdaptor = job.adaptor || '';
      const currentPackageMatch = currentAdaptor.match(/(.+?)@/);
      const currentPackage = currentPackageMatch
        ? currentPackageMatch[1]
        : currentAdaptor;

      // If selecting the same adaptor, just close picker and open configure modal (no confirmation needed)
      if (selectedPackage === currentPackage) {
        setIsAdaptorPickerOpen(false);
        setIsConfigureModalOpen(true);
        return;
      }

      // Check if job has credentials
      const hasCredentials =
        job.project_credential_id || job.keychain_credential_id;

      if (hasCredentials) {
        // Store selection and show confirmation
        setPendingAdaptorSelection(adaptorName);
        setIsAdaptorPickerOpen(false);
        setIsAdaptorChangeConfirmationOpen(true);
      } else {
        // No credentials, proceed directly with adaptor change
        const fullAdaptor = `${selectedPackage}@latest`;

        // Call optional callback (for form sync)
        onAdaptorChangeStart?.();

        // Apply adaptor change immediately (no credential reset needed)
        updateJob(job.id, { adaptor: fullAdaptor });

        setIsAdaptorPickerOpen(false);
        setIsConfigureModalOpen(true);
      }
    },
    [
      job,
      updateJob,
      setIsAdaptorPickerOpen,
      setIsConfigureModalOpen,
      onAdaptorChangeStart,
    ]
  );

  const handleConfirmAdaptorChange = useCallback(() => {
    if (!pendingAdaptorSelection || !job) return;

    // Mark that we're confirming (so onClose knows not to navigate)
    isConfirmingRef.current = true;

    const packageMatch = pendingAdaptorSelection.match(/(.+?)(@|$)/);
    const newPackage = packageMatch ? packageMatch[1] : pendingAdaptorSelection;
    const fullAdaptor = `${newPackage}@latest`;

    // Call optional callback (for form sync)
    onAdaptorChangeStart?.();

    // Apply adaptor change AND reset credentials
    updateJob(job.id, {
      adaptor: fullAdaptor,
      project_credential_id: null,
      keychain_credential_id: null,
    });

    setIsAdaptorChangeConfirmationOpen(false);
    setPendingAdaptorSelection(null);
    setIsConfigureModalOpen(true);

    // Reset the flag after a microtask (after AlertDialog's onClose is called)
    setTimeout(() => {
      isConfirmingRef.current = false;
    }, 0);
  }, [
    job,
    pendingAdaptorSelection,
    updateJob,
    setIsConfigureModalOpen,
    onAdaptorChangeStart,
  ]);

  // Handle modal close (called on cancel button, ESC key, and after confirm button)
  // AlertDialog calls BOTH onConfirm() and onClose() when user clicks Continue button
  // So we need to check if we're confirming to avoid navigating twice
  const handleCloseConfirmation = useCallback(() => {
    setIsAdaptorChangeConfirmationOpen(false);
    setPendingAdaptorSelection(null);

    // Only navigate back to adaptor picker if user canceled (not confirmed)
    // If confirming, handleConfirmAdaptorChange already opened ConfigureModal
    if (!isConfirmingRef.current) {
      setIsAdaptorPickerOpen(true);
    }
  }, [setIsAdaptorPickerOpen]);

  // Explicit cancel handler (same as close, but more semantic)
  const handleCancelAdaptorChange = useCallback(() => {
    handleCloseConfirmation();
  }, [handleCloseConfirmation]);

  return {
    isAdaptorChangeConfirmationOpen,
    handleAdaptorSelect,
    handleConfirmAdaptorChange,
    handleCancelAdaptorChange,
    handleCloseConfirmation,
  };
}
