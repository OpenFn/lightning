import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/react';
import { useCallback, useContext, useEffect, useState } from 'react';

import { useURLState } from '#/react/lib/use-url-state';

import { Tooltip } from '../../components/Tooltip';
import * as dataclipApi from '../api/dataclips';
import { StoreContext } from '../contexts/StoreProvider';
import { useActiveRun, useFollowRun } from '../hooks/useHistory';
import { useSaveBeforeRun } from '../hooks/useSaveBeforeRun';
import {
  useExperimentalFeatures,
  useIsNewWorkflow,
  useLatestSnapshotId,
  useLimits,
  usePermissions,
  useProjectRepoConnection,
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
  initialWorkflowState,
  initialFirstTriggerId,
  isRunPanelOpen = false,
  isIDEOpen = false,
  aiAssistantEnabled = false,
}: {
  children: React.ReactNode[];
  projectId?: string;
  workflowId?: string;
  isSandbox?: boolean;
  initialWorkflowState?: string;
  initialFirstTriggerId?: string;
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
  const [pendingRunId, setPendingRunId] = useState<string | null>(null);
  const sessionWorkflow = useSessionWorkflow();

  const experimentalFeatures = useExperimentalFeatures();
  const lifecycleState = experimentalFeatures
    ? (sessionWorkflow?.state ?? initialWorkflowState)
    : undefined;
  const inSandbox = experimentalFeatures && isSandbox;
  const permissions = usePermissions();
  const canProvisionSandbox = permissions?.can_provision_sandbox ?? false;
  const canArchiveSandbox = permissions?.can_archive_sandbox ?? false;
  const isNewWorkflow = useIsNewWorkflow();
  const [isTransitioning, setIsTransitioning] = useState(false);
  const [showSwitchToDraftDialog, setShowSwitchToDraftDialog] = useState(false);
  const [showGoLiveDialog, setShowGoLiveDialog] = useState(false);
  const [showEditInSandboxPicker, setShowEditInSandboxPicker] = useState(false);
  const [showPromoteDialog, setShowPromoteDialog] = useState(false);
  const activeRun = useActiveRun();
  const { clearRun } = useFollowRun(null);

  useEffect(() => {
    if (pendingRunId && activeRun?.id === pendingRunId) {
      setPendingRunId(null);
      setIsSubmitting(false);
    }
  }, [activeRun?.id, pendingRunId]);

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
  const firstTriggerId = triggers[0]?.id ?? initialFirstTriggerId;

  const {
    isPinnedVersion,
    isViewingAsExecuted,
    isPinnedView,
    version: pinnedVersion,
  } = usePinnedView();

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

  const isViewingNonCurrentVersion = isPinnedVersion || isViewingAsExecuted;

  const versionViewReason = isPinnedVersion
    ? 'You are reading an older version. This acts on the current workflow.'
    : null;

  const promoteViewReason = isPinnedView
    ? 'You are reading the past. Promote acts on the current workflow.'
    : null;

  const sandboxToggleViewReason = isPinnedView
    ? 'You are reading the past. This acts on the current workflow.'
    : null;

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

  const isLiveLocked =
    experimentalFeatures && lifecycleState === 'live' && !inSandbox;

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

  const handleConfirmPromote = useCallback(async (): Promise<boolean> => {
    try {
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

  const handleArchiveSandbox = useCallback(async (): Promise<boolean> => {
    markPromoted();

    try {
      await archiveSandbox();

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
                  run it is retrying, so with the flag on a loaded run is not
                  left without a way to retry it. Without the flag the trigger
                  is required, as on main. */}
              {projectId &&
                workflowId &&
                (firstTriggerId || (isRetryable && experimentalFeatures)) && (
                  <NewRunButton
                    onClick={() => {
                      void (isRetryable
                        ? handleRetryClick()
                        : handleRunClick());
                    }}
                    onRunWithCustomInputClick={handleRunWithCustomInputClick}
                    disabled={isRunPanelOpen || isIDEOpen}
                    forRetry={isRetryable}
                    isRunning={isSubmitting || runIsProcessing}
                    text={isRetryable ? 'Retry' : 'Run'}
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
              clearRun();
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
