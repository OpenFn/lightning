import type { Adaptor } from '#/collaborative-editor/types/adaptor';
import type { Workflow } from '#/collaborative-editor/types/workflow';

import { useAdaptorChangeConfirmation } from '../hooks/useAdaptorChangeConfirmation';
import { useKeyboardShortcut } from '../keyboard';

import { AdaptorSelectionModal } from './AdaptorSelectionModal';
import { AlertDialog } from './AlertDialog';

interface AdaptorSelectorProps {
  /** Whether the adaptor picker modal is open */
  isOpen: boolean;
  /** Setter to control adaptor picker modal state */
  setIsOpen: (open: boolean) => void;
  /** Callback when picker modal is closed (for custom close logic) */
  onClose?: () => void;
  /** Current job (needed for confirmation logic) */
  job: Workflow.Job | null;
  /** Function to update job in Y.Doc */
  updateJob: (jobId: string, updates: Partial<Workflow.Job>) => void;
  /** Setter to control configure modal state */
  setIsConfigureModalOpen: (open: boolean) => void;
  /** Available project adaptors */
  projectAdaptors: Adaptor[];
  /** Optional callback before adaptor change (for form sync in JobForm) */
  onAdaptorChangeStart?: () => void;
}

/**
 * AdaptorSelector - Handles adaptor selection with credential reset confirmation.
 *
 * Coordinates the adaptor selection flow:
 * 1. User picks adaptor from AdaptorSelectionModal
 * 2. If job has credentials, shows AlertDialog for confirmation
 * 3. On confirm, changes adaptor and resets credentials
 * 4. Opens ConfigureAdaptorModal for version/credential selection
 *
 * Used by FullScreenIDE and JobForm for editing existing jobs.
 * WorkflowDiagram uses the base AdaptorSelectionModal directly (no confirmation needed for new jobs).
 */
export function AdaptorSelector({
  isOpen,
  setIsOpen,
  onClose,
  job,
  updateJob,
  setIsConfigureModalOpen,
  projectAdaptors,
  onAdaptorChangeStart,
}: AdaptorSelectorProps) {
  const {
    isAdaptorChangeConfirmationOpen,
    handleAdaptorSelect,
    handleConfirmAdaptorChange,
    handleCloseConfirmation,
  } = useAdaptorChangeConfirmation({
    job,
    updateJob,
    setIsAdaptorPickerOpen: setIsOpen,
    setIsConfigureModalOpen,
    onAdaptorChangeStart,
  });

  const handlePickerClose = () => {
    setIsOpen(false);
    onClose?.();
  };

  // When confirmation is showing, prevent picker's close handler from firing
  const handlePickerCloseGuarded = () => {
    if (!isAdaptorChangeConfirmationOpen) {
      handlePickerClose();
    }
  };

  // Higher-priority ESC handler to close confirmation dialog when open
  // Priority 110 > AdaptorSelectionModal's priority 100
  useKeyboardShortcut(
    'Escape',
    () => {
      handleCloseConfirmation();
    },
    110,
    { enabled: isAdaptorChangeConfirmationOpen }
  );

  return (
    <>
      <AdaptorSelectionModal
        isOpen={isOpen}
        onClose={handlePickerCloseGuarded}
        onSelect={handleAdaptorSelect}
        projectAdaptors={projectAdaptors}
      />

      <AlertDialog
        isOpen={isAdaptorChangeConfirmationOpen}
        onClose={handleCloseConfirmation}
        onConfirm={handleConfirmAdaptorChange}
        title="Change Adaptor?"
        description="Warning: Changing adaptors will reset the credential for this step. Are you sure you want to continue?"
        confirmLabel="Continue"
        cancelLabel="Cancel"
        variant="primary"
      />
    </>
  );
}
