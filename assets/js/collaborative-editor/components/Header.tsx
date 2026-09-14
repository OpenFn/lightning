import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/react';
import { useCallback, useContext, useEffect, useState } from 'react';

import { useURLState } from '#/react/lib/use-url-state';

import { Tooltip } from '../../components/Tooltip';
import * as dataclipApi from '../api/dataclips';
import { StoreContext } from '../contexts/StoreProvider';
import { useActiveRun } from '../hooks/useHistory';
import { useSaveBeforeRun } from '../hooks/useSaveBeforeRun';
import {
  useExperimentalFeatures,
  useIsNewWorkflow,
  useLatestSnapshotId,
  useLimits,
  usePermissions,
  useProjectRepoConnection,
  useSessionContextError,
  useSessionContextLoaded,
  useSessionWorkflow,
  useReleases,
} from '../hooks/useSessionContext';
import { useUICommands } from '../hooks/useUI';
import { useUnsavedChanges } from '../hooks/useUnsavedChanges';
import {
  useCanRun,
  useCanSave,
  useNodeSelection,
  useWorkflowActions,
  useWorkflowEnabled,
  useWorkflowReadOnly,
  useWorkflowSettingsErrors,
  useWorkflowState,
} from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';
import { getCsrfToken } from '../lib/csrf';
import {
  formatChannelErrorMessage,
  isChannelRequestError,
} from '../lib/errors';
import { notifications } from '../lib/notifications';
import {
  AS_RUN_PARAM,
  RELEASE_PARAM,
  SNAPSHOT_PARAM,
  usePinnedView,
} from '../lib/pinnedView';
import { clearPromoted, markPromoted } from '../lib/promoteHandoff';
import { isFinalState } from '../types/history';

import { ActiveCollaborators } from './ActiveCollaborators';
import { AIButton } from './AIButton';
import { AlertDialog } from './AlertDialog';
import { Breadcrumbs } from './Breadcrumbs';
import { Button } from './Button';
import { EditInSandboxPicker } from './EditInSandboxPicker';
import { EmailVerificationBanner } from './EmailVerificationBanner';
import { GitHubSyncModal } from './GitHubSyncModal';
import { Switch } from './inputs/Switch';
import { NewRunButton } from './NewRunButton';
import { PromoteDialog } from './PromoteDialog';
import { ReadOnlyWarning } from './ReadOnlyWarning';
import { ShortcutKeys } from './ShortcutKeys';

/**
 * Save button component - visible in React DevTools
 * Includes tooltip with save status messaging
 * Shows as split button with dropdown when GitHub integration is available
 */
export function SaveButton({
  canSave,
  tooltipMessage,
  onClick,
  repoConnection,
  onSyncClick,
  label = 'Save',
  canSync,
  syncTooltipMessage,
  hasChanges,
}: {
  canSave: boolean;
  tooltipMessage: string;
  onClick: () => void;
  repoConnection: ReturnType<typeof useProjectRepoConnection>;
  onSyncClick: () => void;
  label?: string;
  canSync: boolean;
  syncTooltipMessage: string | null;
  hasChanges: boolean;
}) {
  const hasGitHubIntegration = repoConnection !== null;

  if (!hasGitHubIntegration) {
    return (
      <div className="relative">
        <div className="inline-flex rounded-md shadow-xs z-5">
          <Tooltip
            content={
              canSave ? <ShortcutKeys keys={['mod', 's']} /> : tooltipMessage
            }
            side="bottom"
          >
            <span className="inline-block">
              <Button
                data-testid="save-workflow-button"
                className="phx-submit-loading:opacity-75 cursor-pointer
                  focus:ring-transparent"
                onClick={onClick}
                disabled={!canSave}
              >
                {label}
              </Button>
            </span>
          </Tooltip>
        </div>
        {hasChanges ? (
          <div
            className="absolute -m-1 top-0 right-0 z-10 size-3 bg-danger-500 rounded-full"
            data-is-dirty
          ></div>
        ) : null}
      </div>
    );
  }

  return (
    <div className="relative">
      <div className="inline-flex rounded-md shadow-xs z-5">
        <Tooltip
          content={
            canSave ? <ShortcutKeys keys={['mod', 's']} /> : tooltipMessage
          }
          side="bottom"
        >
          <span className="inline-block">
            <Button
              data-testid="save-workflow-button"
              className="rounded-r-none phx-submit-loading:opacity-75
                cursor-pointer focus:ring-transparent"
              onClick={onClick}
              disabled={!canSave}
            >
              {label}
            </Button>
          </span>
        </Tooltip>
        <Menu as="div" className="relative -ml-px block">
          <MenuButton
            disabled={!canSave}
            className="h-full rounded-r-md pr-2 pl-2 text-sm font-semibold
            shadow-xs cursor-pointer disabled:cursor-not-allowed
            bg-primary-600 hover:bg-primary-500
            disabled:bg-primary-300 disabled:hover:bg-primary-300 text-white
            focus-visible:outline-2 focus-visible:outline-offset-2
            focus-visible:outline-primary-600 focus:ring-transparent"
          >
            <span className="sr-only">Open sync options</span>
            <span className="hero-chevron-down w-4 h-4" />
          </MenuButton>
          <MenuItems
            transition
            className="absolute right-0 z-[100] mt-2 w-max origin-top-right
          rounded-md bg-white py-1 shadow-lg outline outline-black/5
          transition data-closed:scale-95 data-closed:transform
          data-closed:opacity-0 data-enter:duration-200 data-enter:ease-out
          data-leave:duration-75 data-leave:ease-in"
          >
            <MenuItem>
              <Tooltip
                content={
                  canSave && canSync ? (
                    <ShortcutKeys keys={['mod', 'shift', 's']} />
                  ) : !canSync && syncTooltipMessage ? (
                    syncTooltipMessage
                  ) : (
                    tooltipMessage
                  )
                }
                side="bottom"
              >
                <button
                  type="button"
                  onClick={onSyncClick}
                  disabled={!canSave || !canSync}
                  className="block w-full text-left px-4 py-2 text-sm text-gray-700
              data-focus:bg-gray-100 data-focus:outline-hidden
              disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Save & Sync
                </button>
              </Tooltip>
            </MenuItem>
          </MenuItems>
        </Menu>
      </div>
      {hasChanges ? (
        <div
          className="absolute -m-1 top-0 right-0 z-10 size-3 bg-danger-500 rounded-full"
          data-is-dirty
        ></div>
      ) : null}
    </div>
  );
}
SaveButton.displayName = 'SaveButton';

// Turn a refused lifecycle transition into something actionable. The activation
// limit, a permission change and a deleted workflow all reply with real text;
// only a genuinely unexpected failure earns "try again".
function describeLifecycleError(error: unknown): string {
  if (isChannelRequestError(error)) {
    return formatChannelErrorMessage({
      errors: error.errors as { base?: string[] } & Record<string, string[]>,
      type: error.type,
    });
  }

  return error instanceof Error ? error.message : 'Please try again.';
}

export function Header({
  children,
  projectId,
  workflowId,
  isSandbox = false,
  isRunPanelOpen = false,
  isIDEOpen = false,
  aiAssistantEnabled = false,
}: {
  children: React.ReactNode[];
  projectId?: string;
  workflowId?: string;
  isSandbox?: boolean;
  isRunPanelOpen?: boolean;
  isIDEOpen?: boolean;
  aiAssistantEnabled?: boolean;
}) {
  // IMPORTANT: All hooks must be called unconditionally before any early returns or conditional logic
  const { params, updateSearchParams } = useURLState();
  const { selectNode } = useNodeSelection();
  const {
    saveWorkflow,
    goLive,
    switchToDraft,
    promote,
    checkPromote,
    archiveSandbox,
  } = useWorkflowActions();
  const { canSave, tooltipMessage } = useCanSave();
  const { enabled, setEnabled } = useWorkflowEnabled();
  const triggers = useWorkflowState(state => state.triggers);
  // Two answers, because the pinned-version block applies to a fresh run and
  // not to a retry. `canRun` gates starting something new; `canRunOrRetry`
  // gates the control that does whichever the loaded run calls for.
  const { canRun } = useCanRun();
  const { openRunPanel, openGitHubSyncModal } = useUICommands();
  const repoConnection = useProjectRepoConnection();
  const { hasErrors: hasSettingsErrors } = useWorkflowSettingsErrors();
  const limits = useLimits();
  const { isReadOnly, reason: readOnlyReason } = useWorkflowReadOnly();
  const { hasChanges } = useUnsavedChanges();
  const saveBeforeRun = useSaveBeforeRun(saveWorkflow);
  const storeContext = useContext(StoreContext);
  const getLimits = storeContext?.sessionContextStore.getLimits;
  const [isSubmitting, setIsSubmitting] = useState(false);
  // The run just started, held until it actually arrives. Dropping the
  // submitting state when the request returns left a gap before the new run
  // reached the history, and the button flipped back from Processing to Run and
  // then to Processing again. The IDE already waits like this.
  const [pendingRunId, setPendingRunId] = useState<string | null>(null);
  const sessionWorkflow = useSessionWorkflow();

  // The whole sandboxes-and-releases experience hangs off this one flag. Every
  // action it added is already guarded by the lifecycle state or by being inside
  // a sandbox, so reading both as absent when the flag is off leaves the header
  // exactly the shape it had before any of this existed. One gate, rather than a
  // condition bolted onto each button, so a new action cannot be added and
  // forget to check.
  const experimentalFeatures = useExperimentalFeatures();
  const lifecycleState = experimentalFeatures
    ? sessionWorkflow?.state
    : undefined;
  const inSandbox = experimentalFeatures && isSandbox;
  const permissions = usePermissions();
  const canProvisionSandbox = permissions?.can_provision_sandbox ?? false;
  const canArchiveSandbox = permissions?.can_archive_sandbox ?? false;
  const isNewWorkflow = useIsNewWorkflow();
  const [isTransitioning, setIsTransitioning] = useState(false);
  const [showSwitchToDraftDialog, setShowSwitchToDraftDialog] = useState(false);
  // Going live turns the triggers on and starts processing real data. Every
  // other irreversible action here confirms first; this was the one that did
  // not, and it is the one that reaches production.
  const [showGoLiveDialog, setShowGoLiveDialog] = useState(false);
  const [showEditInSandboxPicker, setShowEditInSandboxPicker] = useState(false);
  const [showPromoteDialog, setShowPromoteDialog] = useState(false);
  const activeRun = useActiveRun();

  // Two effects, not one, the way the IDE does it. The arrival has to watch the
  // run, and the timeout must not: folded together and keyed on the run, the
  // clock restarted whenever some other run became active; keyed on the pending
  // id alone, the arrival was read from the render before the run existed and
  // never fired, so the button sat on Processing for the full thirty seconds
  // after a run had already finished.
  useEffect(() => {
    if (pendingRunId && activeRun?.id === pendingRunId) {
      setPendingRunId(null);
      setIsSubmitting(false);
    }
  }, [activeRun?.id, pendingRunId]);

  // If the run never reaches us, the button must not stay stuck.
  useEffect(() => {
    if (!pendingRunId) return;

    const timeoutId = setTimeout(() => {
      setPendingRunId(null);
      setIsSubmitting(false);
    }, 30_000);

    return () => {
      clearTimeout(timeoutId);
    };
  }, [pendingRunId]);
  const runIsProcessing = activeRun ? !isFinalState(activeRun.state) : false;
  const followedRunId = params.run ?? null;
  const isRetryable =
    !!followedRunId &&
    !!activeRun &&
    isFinalState(activeRun.state) &&
    !!activeRun.steps?.length;

  // Check GitHub sync limit
  const githubSyncLimit = limits.github_sync ?? {
    allowed: true,
    message: null,
  };

  // Derived values after all hooks are called
  const firstTriggerId = triggers[0]?.id;

  // Which view of the past, if any, the URL is asking for.
  const {
    isPinnedVersion,
    isViewingAsExecuted,
    isPinnedView,
    version: pinnedVersion,
  } = usePinnedView();

  // Asks for a transition, then moves the URL to match. The channel resolves
  // the live document itself, so it does not matter which document this socket
  // is reading: no waiting for a room change, and nothing to get out of order.
  const requestTransition = useCallback(
    (
      target: 'draft' | 'live',
      afterParams: Record<string, string | null>,
      errorTitle: string
    ) => {
      setIsTransitioning(true);

      void (target === 'live' ? goLive() : switchToDraft())
        .then(() => {
          updateSearchParams(afterParams);
          return null;
        })
        .catch((error: unknown) => {
          // The refusals these buttons can hit all carry actionable text: the
          // activation limit, a permission change, a deleted workflow. "Try
          // again" would be wrong for every one of them.
          notifications.alert({
            title: errorTitle,
            description: describeLifecycleError(error),
          });
        })
        .finally(() => {
          setIsTransitioning(false);
        });
    },
    [goLive, switchToDraft, updateSearchParams]
  );

  // The Live badge describes the workflow's current state, which would be a lie
  // on these views, so it is suppressed and the version badge carries the
  // context instead.
  // Only the badge and the flag-off switch read this now. The lifecycle and
  // sandbox actions carry their own reasons, and Switch to draft is deliberately
  // offered while reading a run, which is where fixing one starts.
  const isViewingNonCurrentVersion = isPinnedVersion || isViewingAsExecuted;

  // These act on the current workflow rather than on what is being read, so a
  // pinned version refuses them and says why. They used to be hidden, which
  // left a header with nothing in it and nothing to explain the view.
  //
  // A run view is deliberately not included. Reading a failed run is where
  // fixing one starts, and these are the way out of it: Switch to draft and
  // Edit in sandbox both carry the run's input into the fix. A pinned version
  // has no run to carry, so there is nothing to preserve by allowing them.
  const versionViewReason = isPinnedVersion
    ? 'You are reading an older version. This acts on the current workflow.'
    : null;

  // Promote is the exception: it saves first, and every view of the past
  // refuses that save, so a run's own view stops it too.
  const promoteViewReason = isPinnedView
    ? 'You are reading the past. Promote acts on the current workflow.'
    : null;

  // The sandbox switch is refused on any view of the past, and a run's own view
  // left it disabled describing what it does rather than why it cannot be used.
  const sandboxToggleViewReason = isPinnedView
    ? 'You are reading the past. This acts on the current workflow.'
    : null;

  // A retry runs the content that is live now, whatever is on screen. The
  // button does not say so, because retrying always means that, but the
  // confirmation names the version so the record of what just ran is clear.
  const latestSnapshotId = useLatestSnapshotId();

  const releases = useReleases();
  const liveVersionNumber =
    releases.find(
      version =>
        version.snapshot_id != null && version.snapshot_id === latestSnapshotId
    )?.version_number ?? null;

  // Determine AI button disabled message based on priority
  const aiButtonDisabledMessage = !aiAssistantEnabled
    ? 'Your instance does not have build-time AI enabled. Contact your administrator or support@openfn.org to configure it.'
    : isPinnedVersion
      ? 'Switch to the latest version of this workflow to use the AI Assistant.'
      : undefined;

  const showChangeIndicator = hasChanges && canSave;

  const { canRun: canRunOrRetry } = useCanRun({ forRetry: isRetryable });

  // The lifecycle lock as the header sees it, and whether we know it yet.
  //
  // Everything this depends on, the flag included, arrives with the session
  // context, so before it lands the honest answer is "unknown" rather than
  // "flag off, draft". Treating unknown as locked holds Save back until the
  // header can settle in one go: a control appearing is fine, one vanishing
  // under the cursor is not.
  // An answer, not necessarily a good one. A context request that fails leaves
  // `lastUpdated` null forever and there is no retry, so waiting only on the
  // success would take Save away permanently, flag-off users included.
  // Both called unconditionally: `||` short-circuits, and a hook that only runs
  // on one branch changes the hook order between renders, which React refuses.
  const contextLoaded = useSessionContextLoaded();
  const contextError = useSessionContextError();
  const sessionContextLoaded = contextLoaded || contextError !== null;
  //
  // Unknown counts as locked, for everyone. The flag itself arrives with the
  // context, so before it lands "flag off" and "we do not know yet" are the
  // same answer, and treating unknown as unlocked renders Save and then takes
  // it away again on a live workflow. Nobody can save during that window
  // anyway, because the session is not connected, so what a flag-off user
  // loses is the sight of a button they could not have pressed.
  const isLiveLocked =
    !sessionContextLoaded ||
    (experimentalFeatures &&
      lifecycleState === 'live' &&
      !inSandbox &&
      // Not while reading the past. There the button is refused by the view,
      // which is a reason it can carry; dropping it would leave that screen
      // with nothing saying why it cannot be edited.
      !isPinnedView);

  // A retry runs the latest version, never the one on screen, so while an older
  // version is being read the button has to say so before the click rather than
  // in the toast afterwards. It is deliberately silent otherwise: on the latest
  // version there is nothing surprising to warn about.
  const retryTooltip =
    isRetryable && isPinnedVersion
      ? `Runs this input on the latest version${
          liveVersionNumber === null ? '' : ` (v${liveVersionNumber})`
        }${pinnedVersion === null ? '' : `, not v${pinnedVersion}`}.`
      : undefined;

  const handleRunClick = useCallback(async () => {
    if (!firstTriggerId || !projectId || !workflowId) return;

    setIsSubmitting(true);
    try {
      const saved = await saveBeforeRun();
      const response = await dataclipApi.submitManualRun({
        workflowId,
        projectId,
        triggerId: firstTriggerId,
      });
      notifications.success({
        title: 'Run started',
        description: saved
          ? 'Saved latest changes and created new work order'
          : 'Created new work order',
      });
      if (getLimits) void getLimits('new_run');
      setPendingRunId(response.data.run_id);
      updateSearchParams({ run: response.data.run_id });
    } catch (error) {
      notifications.alert({
        title: 'Failed to submit run',
        description:
          error instanceof Error ? error.message : 'An unknown error occurred',
      });
      setIsSubmitting(false);
    }
  }, [
    firstTriggerId,
    projectId,
    workflowId,
    saveBeforeRun,
    getLimits,
    updateSearchParams,
  ]);

  // The one retry path, from wherever a run is loaded: the run's own view, a
  // version being read, or the live workflow. It runs the content that is live
  // rather than whatever is on screen, which is why the toast names the version
  // it ran. The save underneath is a no-op unless there is something to save
  // and saving is allowed. It lands on the new run, since the canvas that was
  // being read is no longer the subject.
  const handleRetryClick = useCallback(async () => {
    const firstStep = activeRun?.steps?.[0];
    if (!followedRunId || !firstStep || !projectId) return;

    setIsSubmitting(true);
    try {
      const saved = await saveBeforeRun();

      const response = await fetch(
        `/projects/${projectId}/runs/${followedRunId}/retry`,
        {
          method: 'POST',
          credentials: 'same-origin',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': getCsrfToken() || '',
          },
          body: JSON.stringify({ step_id: firstStep.id }),
        }
      );

      if (!response.ok) {
        const error = (await response.json()) as { error?: string };
        throw new Error(error.error || 'Failed to retry run');
      }

      const result = (await response.json()) as { data: { run_id: string } };

      const ranOn =
        liveVersionNumber === null
          ? 'the latest version'
          : `v${liveVersionNumber}`;

      notifications.success({
        title: 'Retry started',
        description: saved
          ? `Saved latest changes and re-running this input on ${ranOn}.`
          : `Running this input on ${ranOn}.`,
      });

      if (getLimits) void getLimits('new_run');
      // Every pinned view goes, not just the run's own: a retry runs the
      // content that is live, so staying on `?v=` left the badge naming a
      // version the new run did not execute.
      //
      // Same rule as the run panel's retry, flag and all. Two controls doing
      // the same thing should not leave the URL in two different states.
      updateSearchParams(
        experimentalFeatures
          ? {
              [RELEASE_PARAM]: null,
              [SNAPSHOT_PARAM]: null,
              [AS_RUN_PARAM]: null,
              step: null,
              run: result.data.run_id,
            }
          : { run: result.data.run_id }
      );
      setPendingRunId(result.data.run_id);
    } catch (error) {
      notifications.alert({
        title: 'Retry failed',
        description: error instanceof Error ? error.message : 'Unknown error',
      });
      setIsSubmitting(false);
    }
  }, [
    activeRun,
    followedRunId,
    projectId,
    liveVersionNumber,
    experimentalFeatures,
    saveBeforeRun,
    getLimits,
    updateSearchParams,
  ]);

  const handleRunWithCustomInputClick = useCallback(() => {
    if (firstTriggerId) {
      selectNode(firstTriggerId);
      updateSearchParams({ panel: 'run' });
      openRunPanel({
        triggerId: firstTriggerId,
        entryPoint: 'custom-input',
      });
    }
  }, [firstTriggerId, openRunPanel, selectNode, updateSearchParams]);

  // Phase one of the promote flow. Promote always reflects the current editor
  // state, so we save first (silently) and only merge once that succeeds; a
  // failed save aborts without promoting. Promote now MERGES ONLY: it does not
  // archive the sandbox, so on success we do NOT navigate. Instead we stash the
  // parent + workflow ids and resolve true, letting the dialog advance to its
  // success step where archiving is offered as an optional second action.
  // Failures (save or merge) are surfaced inline and resolve false so the dialog
  // stays on its confirm step.
  const handleConfirmPromote = useCallback(async (): Promise<boolean> => {
    try {
      // The dialog owns every outcome here, so the save underneath it must not
      // toast on its own.
      await saveWorkflow({ notify: 'none' });
    } catch (error) {
      const description = isChannelRequestError(error)
        ? formatChannelErrorMessage({
            errors: error.errors as { base?: string[] } & Record<
              string,
              string[]
            >,
            type: error.type,
          })
        : error instanceof Error
          ? error.message
          : 'Please try again.';
      notifications.alert({
        title: 'Could not save before promoting',
        description,
      });
      return false;
    }

    try {
      await promote();
      return true;
    } catch (error) {
      const description = isChannelRequestError(error)
        ? formatChannelErrorMessage({
            errors: error.errors as { base?: string[] } & Record<
              string,
              string[]
            >,
            type: error.type,
          })
        : 'Please try again.';
      notifications.alert({
        title: 'Could not promote',
        description,
      });
      return false;
    }
  }, [promote, saveWorkflow]);

  // Phase two, archive path. Retires the sandbox and lets the server carry the
  // socket into the parent, which is a different Y.Doc session. No toast is
  // raised here: the reload would destroy it. The promote is confirmed across
  // the navigation instead (see promoteHandoff), because the flash the server
  // sends speaks only of the archive. Errors, which don't navigate, are
  // surfaced inline and resolve false so the dialog stays on its success step.
  const handleArchiveSandbox = useCallback(async (): Promise<boolean> => {
    // Marked before the call, because the server's redirect can land before
    // this promise resolves. Cleared again if the archive refuses, so a sandbox
    // we are still sitting in never claims to have been retired.
    markPromoted();

    try {
      await archiveSandbox();

      // Navigation is the server's: archiving schedules the sandbox for
      // deletion, and the LiveView's teardown hook redirects every socket on it
      // to the parent, landing on the parent's copy of this workflow. Racing it
      // from here only produced a second navigation to the same place.
      return true;
    } catch (error) {
      clearPromoted();

      const description = isChannelRequestError(error)
        ? formatChannelErrorMessage({
            errors: error.errors as { base?: string[] } & Record<
              string,
              string[]
            >,
            type: error.type,
          })
        : 'Please try again.';
      notifications.alert({
        title: 'Could not archive sandbox',
        description,
      });
      return false;
    }
  }, [archiveSandbox]);

  // Phase two, keep path. Close the dialog and stay in the sandbox (no
  // navigation) so the user can switch to another workflow and promote it too.
  // The toast is shown inline here since we are not reloading.
  const handleKeepSandbox = useCallback(() => {
    setShowPromoteDialog(false);
    notifications.success({
      title: 'Workflow promoted',
      description:
        'You can keep editing or promote another workflow from this sandbox.',
    });
  }, []);

  const handleCancelPromote = useCallback(() => {
    setShowPromoteDialog(false);
  }, []);

  useKeyboardShortcut(
    'Control+Enter, Meta+Enter',
    () => {
      if (isRetryable) {
        void handleRetryClick();
      } else {
        void handleRunClick();
      }
    },
    0,
    {
      enabled:
        canRunOrRetry &&
        !isRunPanelOpen &&
        !isIDEOpen &&
        !isSubmitting &&
        !runIsProcessing &&
        !!projectId &&
        !!workflowId &&
        (isRetryable || !!firstTriggerId),
    }
  );

  useKeyboardShortcut(
    'Control+Shift+Enter, Meta+Shift+Enter',
    () => {
      handleRunWithCustomInputClick();
    },
    0,
    {
      enabled:
        canRun &&
        !isRunPanelOpen &&
        !isIDEOpen &&
        !!projectId &&
        !!workflowId &&
        !!firstTriggerId,
    }
  );

  useKeyboardShortcut(
    'Control+s, Meta+s',
    () => {
      void saveWorkflow();
    },
    0,
    { enabled: canSave }
  );

  useKeyboardShortcut(
    'Control+Shift+s, Meta+Shift+s',
    () => {
      openGitHubSyncModal();
    },
    0,
    { enabled: canSave && !!repoConnection && githubSyncLimit.allowed }
  );

  return (
    <>
      <EmailVerificationBanner />

      <div className="flex-none bg-white shadow-xs border-b border-gray-200 relative z-50">
        <div className="mx-auto sm:px-4 lg:px-4 py-6 flex items-center h-20 text-sm gap-2">
          <div className="flex min-w-0 items-center">
            <Breadcrumbs>{children}</Breadcrumbs>
          </div>
          {/* The Live badge already implies read-only, so suppress the
              redundant "Read-only" pill whenever the Live badge is shown for
              the current live version. Still show it for a pinned/deleted
              read-only view, where "Live" (the current state) doesn't explain
              why this view is read-only. */}
          {!(
            lifecycleState === 'live' &&
            !isNewWorkflow &&
            !inSandbox &&
            readOnlyReason !== 'pinned_version' &&
            readOnlyReason !== 'as_run' &&
            readOnlyReason !== 'deleted'
          ) && <ReadOnlyWarning className="ml-3" />}
          {lifecycleState &&
            !isNewWorkflow &&
            !inSandbox &&
            !isViewingNonCurrentVersion && (
              <Tooltip
                content={
                  lifecycleState === 'live'
                    ? "This is the live version. It's running in production with its triggers on, and it's read-only here, so switch it to draft or edit it in a sandbox to make changes."
                    : 'This is the editable working version, not the one live in production. Go live to put it into production.'
                }
                side="bottom"
              >
                <span
                  data-testid="workflow-lifecycle-badge"
                  className={
                    'self-center rounded-md px-2 py-1 text-xs font-medium ' +
                    (lifecycleState === 'live'
                      ? 'bg-green-100 text-green-800'
                      : 'bg-gray-100 text-gray-700')
                  }
                >
                  {lifecycleState === 'live' ? 'Live' : 'Draft'}
                </span>
              </Tooltip>
            )}
          <ActiveCollaborators className="ml-2" />
          <div className="grow ml-2"></div>

          <div className="flex flex-row gap-2 items-center">
            <div className="flex flex-row gap-2 items-center">
              {/* Turning the workflow on and off. Only without experimental
                  features: with them, the lifecycle badge and Go live /
                  Switch to draft answer the same question, and two controls
                  for one thing would contradict each other. */}
              {!experimentalFeatures && !isViewingNonCurrentVersion && (
                <span className="inline-flex items-center">
                  <Switch
                    checked={enabled ?? false}
                    onChange={setEnabled}
                    disabled={isReadOnly}
                  />
                </span>
              )}

              <div>
                <button
                  type="button"
                  onClick={() => {
                    const currentPanel = params.panel;
                    updateSearchParams({
                      panel: currentPanel === 'settings' ? null : 'settings',
                    });
                  }}
                  className={`w-6 h-6 place-self-center ${
                    hasSettingsErrors
                      ? 'text-danger-500 hover:text-danger-400 cursor-pointer'
                      : 'text-slate-500 hover:text-slate-400 cursor-pointer'
                  }`}
                >
                  <span className="hero-adjustments-vertical"></span>
                </button>
              </div>
              <div
                className="hidden"
                phx-disconnected='[["show",{"transition":[["fade-in"],[],[]]}]]'
                phx-connected='[["hide",{"transition":[["fade-out"],[],[]]}]]'
              >
                <span className="hero-signal-slash w-6 h-6 place-self-center mr-2 text-red-500"></span>
              </div>
            </div>
            <div className="relative flex gap-2">
              {!isNewWorkflow && !inSandbox && lifecycleState === 'draft' && (
                <Tooltip
                  content={
                    versionViewReason ??
                    (isReadOnly ? 'You cannot go live on this version' : null)
                  }
                  side="bottom"
                >
                  <span className="inline-block">
                    <Button
                      data-testid="go-live-button"
                      className="inline-flex items-center"
                      disabled={
                        isReadOnly || isTransitioning || isPinnedVersion
                      }
                      onClick={() => {
                        setShowGoLiveDialog(true);
                      }}
                    >
                      Go live
                    </Button>
                  </span>
                </Tooltip>
              )}
              {!isNewWorkflow && !inSandbox && lifecycleState === 'live' && (
                <Tooltip content={versionViewReason} side="bottom">
                  <span className="inline-block">
                    <Button
                      variant="secondary"
                      data-testid="switch-to-draft-button"
                      className="inline-flex items-center hover:bg-gray-50
                          disabled:hover:inset-ring-gray-300"
                      disabled={isTransitioning || isPinnedVersion}
                      onClick={() => {
                        setShowSwitchToDraftDialog(true);
                      }}
                    >
                      Switch to draft
                    </Button>
                  </span>
                </Tooltip>
              )}
              {!isNewWorkflow && inSandbox && (
                <Tooltip
                  content={
                    sandboxToggleViewReason ??
                    (lifecycleState === 'live'
                      ? 'Turn the sandbox off and its triggers stop answering.'
                      : "Turn the sandbox on and its own webhook URL answers, and its cron triggers fire. The parent's live workflow is untouched.")
                  }
                  side="bottom"
                >
                  <span className="inline-block">
                    <Button
                      variant="secondary"
                      data-testid="toggle-sandbox-button"
                      className="inline-flex items-center hover:bg-gray-50
                        disabled:hover:inset-ring-gray-300"
                      disabled={
                        isReadOnly || isTransitioning || isPinnedVersion
                      }
                      onClick={() => {
                        const turningOn = lifecycleState !== 'live';
                        requestTransition(
                          turningOn ? 'live' : 'draft',
                          {
                            [RELEASE_PARAM]: null,
                            [SNAPSHOT_PARAM]: null,
                            [AS_RUN_PARAM]: null,
                            step: null,
                          },
                          turningOn
                            ? 'Could not turn the sandbox on'
                            : 'Could not turn the sandbox off'
                        );
                      }}
                    >
                      {lifecycleState === 'live' ? 'Turn off' : 'Turn on'}
                    </Button>
                  </span>
                </Tooltip>
              )}
              {!isNewWorkflow && inSandbox && (
                <Tooltip content={promoteViewReason} side="bottom">
                  <span className="inline-block">
                    <Button
                      data-testid="promote-sandbox-button"
                      className="inline-flex items-center gap-1"
                      // Promote saves before it merges, and a view of the past
                      // is refused that save. A run's own view is as refused as
                      // a pinned version, so both are covered.
                      disabled={isPinnedView}
                      onClick={() => {
                        setShowPromoteDialog(true);
                      }}
                    >
                      Promote
                    </Button>
                  </span>
                </Tooltip>
              )}
              {lifecycleState === 'live' && !inSandbox && !isNewWorkflow && (
                <Tooltip
                  content={
                    versionViewReason ??
                    (canProvisionSandbox
                      ? null
                      : 'You do not have permission to create a sandbox in this project.')
                  }
                  side="bottom"
                >
                  <span className="inline-block">
                    <Button
                      data-testid="edit-in-sandbox-button"
                      className="inline-flex items-center"
                      disabled={!canProvisionSandbox || isPinnedVersion}
                      onClick={() => {
                        if (!canProvisionSandbox) return;
                        setShowEditInSandboxPicker(true);
                      }}
                    >
                      Edit in sandbox
                    </Button>
                  </span>
                </Tooltip>
              )}
              {/* A run needs a trigger to start from; a retry needs only the
                  run it is retrying. Gating both on the trigger would leave a
                  loaded run with no way to retry it. */}
              {projectId && workflowId && (firstTriggerId || isRetryable) && (
                <NewRunButton
                  onClick={() => {
                    void (isRetryable ? handleRetryClick() : handleRunClick());
                  }}
                  onRunWithCustomInputClick={handleRunWithCustomInputClick}
                  disabled={isRunPanelOpen || isIDEOpen}
                  forRetry={isRetryable}
                  isRunning={isSubmitting || runIsProcessing}
                  text={isRetryable ? 'Run (Retry)' : 'Run'}
                  enabledTooltip={retryTooltip}
                />
              )}
              {/* A live workflow outside a sandbox can never be saved, and the
                  Live badge and Switch to draft beside it already say why, so
                  the button goes rather than sitting there dead. Everywhere
                  else it stays and carries its own reason: without the flag
                  there is no badge, and on a pinned version the reason is the
                  view rather than the lifecycle. */}
              {!isLiveLocked && (
                <SaveButton
                  canSave={canSave && !hasSettingsErrors}
                  tooltipMessage={tooltipMessage}
                  onClick={() => void saveWorkflow()}
                  repoConnection={repoConnection}
                  onSyncClick={openGitHubSyncModal}
                  label={isNewWorkflow ? 'Create' : 'Save'}
                  canSync={githubSyncLimit.allowed}
                  syncTooltipMessage={githubSyncLimit.message}
                  hasChanges={showChangeIndicator}
                />
              )}
            </div>
          </div>

          <AIButton
            className="ml-2"
            disabled={isPinnedVersion || !aiAssistantEnabled}
            disabledMessage={aiButtonDisabledMessage}
          />

          <GitHubSyncModal />

          <AlertDialog
            isOpen={showGoLiveDialog}
            onClose={() => {
              setShowGoLiveDialog(false);
            }}
            onConfirm={() => {
              setShowGoLiveDialog(false);
              // The run goes too. Going live writes a new version, so a run
              // selected beforehand no longer matches what is live, and the
              // canvas would answer that by opening it as it executed: you
              // confirm Go live and land read-only in a view of an old run
              // rather than looking at what you just published.
              requestTransition(
                'live',
                {
                  [RELEASE_PARAM]: null,
                  [SNAPSHOT_PARAM]: null,
                  [AS_RUN_PARAM]: null,
                  step: null,
                  run: null,
                },
                'Could not go live'
              );
            }}
            title="Go live"
            description="This puts the workflow into production. Its triggers will be turned on and it will start processing real data."
            confirmLabel="Go live"
            variant="primary"
          />

          <AlertDialog
            isOpen={showSwitchToDraftDialog}
            onClose={() => {
              setShowSwitchToDraftDialog(false);
            }}
            onConfirm={() => {
              setShowSwitchToDraftDialog(false);
              // Coming from a failed run, both the run and its input come
              // along. Switching to draft does not change the content, it
              // unlocks it, so the run being read still describes what is on
              // screen: dropping it threw away the logs and the failing step at
              // the moment the fix starts, which is the one thing the person
              // came for. The input comes too, so the run panel opens ready to
              // put the same data through again.
              //
              // Every pinned parameter goes, because only the latest version
              // can be edited and that is also what production was running.
              // Wanting the older content back is Restore, a different action.

              const runInput = activeRun?.steps?.[0]?.input_dataclip_id ?? null;

              requestTransition(
                'draft',
                {
                  [RELEASE_PARAM]: null,
                  [SNAPSHOT_PARAM]: null,
                  [AS_RUN_PARAM]: null,
                  step: null,
                  run: activeRun?.id ?? params.run ?? null,
                  ...(runInput ? { panel: 'run', dataclip: runInput } : {}),
                },
                'Could not switch to draft'
              );
            }}
            title="Switch to draft"
            description="This takes the workflow out of production. Its triggers will be turned off and it will stop processing data until you go live again."
            confirmLabel="Switch to draft"
            variant="primary"
          />

          <PromoteDialog
            isOpen={showPromoteDialog}
            canArchiveSandbox={canArchiveSandbox}
            onConfirmPromote={handleConfirmPromote}
            onArchive={handleArchiveSandbox}
            onKeep={handleKeepSandbox}
            onCancel={handleCancelPromote}
            onCheckDivergence={checkPromote}
          />

          <EditInSandboxPicker
            isOpen={showEditInSandboxPicker}
            onClose={() => {
              setShowEditInSandboxPicker(false);
            }}
          />
        </div>
      </div>
    </>
  );
}
