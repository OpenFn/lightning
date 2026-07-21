import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/react';
import { useCallback, useContext, useRef, useState } from 'react';

import { useURLState } from '#/react/lib/use-url-state';

import { Tooltip } from '../../components/Tooltip';
import { buildClassicalEditorUrl } from '../../utils/editorUrlConversion';
import * as dataclipApi from '../api/dataclips';
import { StoreContext } from '../contexts/StoreProvider';
import { channelRequest } from '../hooks/useChannel';
import { useActiveRun } from '../hooks/useHistory';
import { useSession } from '../hooks/useSession';
import {
  useIsNewWorkflow,
  useLimits,
  usePermissions,
  useProjectRepoConnection,
  useSessionWorkflow,
} from '../hooks/useSessionContext';
import {
  useImportPanelState,
  useIsCreateWorkflowPanelCollapsed,
  useTemplatePanel,
  useUICommands,
} from '../hooks/useUI';
import { useUnsavedChanges } from '../hooks/useUnsavedChanges';
import {
  useCanRun,
  useCanSave,
  useNodeSelection,
  useWorkflowActions,
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
import { isFinalState } from '../types/history';

import { ActiveCollaborators } from './ActiveCollaborators';
import { AIButton } from './AIButton';
import { AlertDialog } from './AlertDialog';
import { Breadcrumbs } from './Breadcrumbs';
import { EditInSandboxPicker } from './EditInSandboxPicker';
import { EmailVerificationBanner } from './EmailVerificationBanner';
import { GitHubSyncModal } from './GitHubSyncModal';
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
            <button
              type="button"
              data-testid="save-workflow-button"
              className="rounded-md text-sm font-semibold shadow-xs
            phx-submit-loading:opacity-75 cursor-pointer
            disabled:cursor-not-allowed disabled:bg-primary-300 px-3 py-2
            bg-primary-600 hover:bg-primary-500
            disabled:hover:bg-primary-300 text-white
            focus-visible:outline-2 focus-visible:outline-offset-2
            focus-visible:outline-primary-600 focus:ring-transparent"
              onClick={onClick}
              disabled={!canSave}
            >
              {label}
            </button>
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
          <button
            type="button"
            data-testid="save-workflow-button"
            className="rounded-l-md text-sm font-semibold shadow-xs
            phx-submit-loading:opacity-75 cursor-pointer
            disabled:cursor-not-allowed disabled:bg-primary-300 px-3 py-2
            bg-primary-600 hover:bg-primary-500
            disabled:hover:bg-primary-300 text-white
            focus-visible:outline-2 focus-visible:outline-offset-2
            focus-visible:outline-primary-600 focus:ring-transparent"
            onClick={onClick}
            disabled={!canSave}
          >
            {label}
          </button>
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
  const { saveWorkflow, goLive, switchToDraft, promote, archiveSandbox } =
    useWorkflowActions();
  const { canSave, tooltipMessage } = useCanSave();
  const triggers = useWorkflowState(state => state.triggers);
  const jobs = useWorkflowState(state => state.jobs);
  const { canRun } = useCanRun();
  const { openRunPanel, openGitHubSyncModal } = useUICommands();
  const repoConnection = useProjectRepoConnection();
  const { hasErrors: hasSettingsErrors } = useWorkflowSettingsErrors();
  const isNewWorkflow = useIsNewWorkflow();
  const isCreateWorkflowPanelCollapsed = useIsCreateWorkflowPanelCollapsed();
  const importPanelState = useImportPanelState();
  const { selectedTemplate } = useTemplatePanel();
  const { provider } = useSession();
  const limits = useLimits();
  const { isReadOnly, reason: readOnlyReason } = useWorkflowReadOnly();
  const { hasChanges } = useUnsavedChanges();
  const storeContext = useContext(StoreContext);
  const getLimits = storeContext?.sessionContextStore.getLimits;
  const [isSubmitting, setIsSubmitting] = useState(false);
  const sessionWorkflow = useSessionWorkflow();
  const lifecycleState = sessionWorkflow?.state;
  const permissions = usePermissions();
  const canProvisionSandbox = permissions?.can_provision_sandbox ?? false;
  const canArchiveSandbox = permissions?.can_archive_sandbox ?? false;
  const [isTransitioning, setIsTransitioning] = useState(false);
  const [showSwitchToDraftDialog, setShowSwitchToDraftDialog] = useState(false);
  const [showEditInSandboxPicker, setShowEditInSandboxPicker] = useState(false);
  const [showPromoteDialog, setShowPromoteDialog] = useState(false);
  // Retains the parent project + workflow ids from a successful merge so the
  // optional archive step can navigate into the parent afterwards.
  const promoteResultRef = useRef<{
    parent_project_id: string;
    workflow_id: string | null;
  } | null>(null);
  const activeRun = useActiveRun();
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
  const isWorkflowEmpty = jobs.length === 0 && triggers.length === 0;
  const currentMethod = params['method'] as 'template' | 'import' | 'ai' | null;

  // Check if viewing a pinned version via URL parameter
  // When ?v= is present, user is viewing a specific version (even if latest)
  const isPinnedVersion = params['v'] !== undefined && params['v'] !== null;

  // Determine AI button disabled message based on priority
  const aiButtonDisabledMessage = !aiAssistantEnabled
    ? 'Your instance does not have build-time AI enabled. Contact your administrator or support@openfn.org to configure it.'
    : isPinnedVersion
      ? 'Switch to the latest version of this workflow to use the AI Assistant.'
      : undefined;

  const showChangeIndicator = hasChanges && canSave && !isNewWorkflow;

  const handleRunClick = useCallback(async () => {
    if (!firstTriggerId || !projectId || !workflowId) return;

    setIsSubmitting(true);
    try {
      await saveWorkflow({ silent: true });
      const response = await dataclipApi.submitManualRun({
        workflowId,
        projectId,
        triggerId: firstTriggerId,
      });
      notifications.success({
        title: 'Run started',
        description: 'Saved latest changes and created new work order',
      });
      if (getLimits) void getLimits('new_run');
      updateSearchParams({ run: response.data.run_id });
    } catch (error) {
      notifications.alert({
        title: 'Failed to submit run',
        description:
          error instanceof Error ? error.message : 'An unknown error occurred',
      });
    } finally {
      setIsSubmitting(false);
    }
  }, [
    firstTriggerId,
    projectId,
    workflowId,
    saveWorkflow,
    getLimits,
    updateSearchParams,
  ]);

  const handleRetryClick = useCallback(async () => {
    if (!followedRunId || !activeRun?.steps?.length || !projectId) return;

    setIsSubmitting(true);
    try {
      await saveWorkflow({ silent: true });

      const firstStep = activeRun.steps[0];
      const retryUrl = `/projects/${projectId}/runs/${followedRunId}/retry`;
      const csrfToken = getCsrfToken();
      const response = await fetch(retryUrl, {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken || '',
        },
        body: JSON.stringify({ step_id: firstStep.id }),
      });

      if (!response.ok) {
        const error = (await response.json()) as { error?: string };
        throw new Error(error.error || 'Failed to retry run');
      }

      const result = (await response.json()) as { data: { run_id: string } };

      notifications.success({
        title: 'Retry started',
        description: 'Saved latest changes and re-running with previous input',
      });

      if (getLimits) void getLimits('new_run');
      updateSearchParams({ run: result.data.run_id });
    } catch (error) {
      notifications.alert({
        title: 'Retry failed',
        description: error instanceof Error ? error.message : 'Unknown error',
      });
    } finally {
      setIsSubmitting(false);
    }
  }, [
    followedRunId,
    activeRun,
    projectId,
    saveWorkflow,
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

  const handleSwitchToLegacyEditor = useCallback(async () => {
    if (!provider?.channel || !projectId || !workflowId) return;

    try {
      await channelRequest(provider.channel, 'switch_to_legacy_editor', {});

      // Build legacy editor URL and navigate
      const legacyUrl = buildClassicalEditorUrl({
        projectId,
        workflowId,
        searchParams: new URLSearchParams(window.location.search),
        isNewWorkflow,
      });
      window.location.href = legacyUrl;
    } catch (error) {
      console.error('Failed to switch to legacy editor:', error);
    }
  }, [provider, projectId, workflowId, isNewWorkflow]);

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
      await saveWorkflow({ silent: true });
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
      promoteResultRef.current = await promote();
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

  // Phase two, archive path. Retires the sandbox, then hard-navigates into the
  // parent (a different Y.Doc session), matching the picker's post-create
  // navigation. The success toast is handed off through the URL (?promoted=1)
  // rather than shown here: firing it before the reload would destroy it. The
  // parent editor reads the marker on load (see PromotedNotice). The parent
  // workflow may be missing, so fall back to the project's workflow index when
  // promote returned a null workflow_id. Errors, which don't navigate, are
  // surfaced inline and resolve false so the dialog stays on its success step.
  const handleArchiveSandbox = useCallback(async (): Promise<boolean> => {
    try {
      const { parent_project_id } = await archiveSandbox();
      const workflowId = promoteResultRef.current?.workflow_id;
      const base = workflowId
        ? `/projects/${parent_project_id}/w/${workflowId}`
        : `/projects/${parent_project_id}/w`;

      window.location.href = `${base}?promoted=1`;
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
        canRun &&
        !isRunPanelOpen &&
        !isIDEOpen &&
        !isNewWorkflow &&
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
        !isNewWorkflow &&
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
            !isSandbox &&
            readOnlyReason !== 'pinned_version' &&
            readOnlyReason !== 'deleted'
          ) && <ReadOnlyWarning className="ml-3" />}
          {lifecycleState && !isNewWorkflow && !isSandbox && (
            <Tooltip
              content={
                lifecycleState === 'live'
                  ? "This is the live version. It's running in production with its triggers on, and it's read-only here, so switch it to draft or edit it in a sandbox to make changes."
                  : 'This is the editable working version, not the one live in production. Go live to promote it, or enable a trigger to test it against real events first.'
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
          {projectId && workflowId && (
            <Tooltip
              content={
                <span>
                  Looking for the old version of the workflow builder? You can
                  switch back for a few more days by clicking this icon. (But it
                  will soon be retired!)
                </span>
              }
              side="bottom"
            >
              <button
                type="button"
                onClick={() => void handleSwitchToLegacyEditor()}
                className="w-6 h-6 place-self-center text-slate-500 hover:text-slate-400 cursor-pointer"
              >
                <span className="hero-question-mark-circle"></span>
              </button>
            </Tooltip>
          )}
          <ActiveCollaborators className="ml-2" />
          <div className="grow ml-2"></div>

          <div className="flex flex-row gap-2 items-center">
            <div className="flex flex-row gap-2 items-center">
              <div>
                <Tooltip
                  content={
                    isNewWorkflow && isWorkflowEmpty
                      ? 'Add a workflow to configure settings'
                      : null
                  }
                  side="bottom"
                >
                  <button
                    type="button"
                    onClick={() => {
                      if (isNewWorkflow && isWorkflowEmpty) return;
                      const currentPanel = params.panel;
                      updateSearchParams({
                        panel: currentPanel === 'settings' ? null : 'settings',
                      });
                    }}
                    disabled={isNewWorkflow && isWorkflowEmpty}
                    className={`w-6 h-6 place-self-center ${
                      hasSettingsErrors
                        ? 'text-danger-500 hover:text-danger-400 cursor-pointer'
                        : isNewWorkflow && isWorkflowEmpty
                          ? 'cursor-not-allowed opacity-50'
                          : 'text-slate-500 hover:text-slate-400 cursor-pointer'
                    }`}
                  >
                    <span className="hero-adjustments-vertical"></span>
                  </button>
                </Tooltip>
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
              {!isNewWorkflow && !isSandbox && lifecycleState === 'draft' && (
                <Tooltip
                  content={
                    isReadOnly ? 'You cannot go live on this version' : null
                  }
                  side="bottom"
                >
                  <button
                    type="button"
                    data-testid="go-live-button"
                    disabled={isReadOnly || isTransitioning}
                    onClick={() => {
                      setIsTransitioning(true);
                      void goLive()
                        .catch(() =>
                          notifications.alert({
                            title: 'Could not go live',
                            description: 'Please try again.',
                          })
                        )
                        .finally(() => {
                          setIsTransitioning(false);
                        });
                    }}
                    className="inline-flex items-center rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-primary-500 disabled:cursor-not-allowed disabled:bg-primary-300 disabled:hover:bg-primary-300"
                  >
                    Go live
                  </button>
                </Tooltip>
              )}
              {!isNewWorkflow && !isSandbox && lifecycleState === 'live' && (
                <button
                  type="button"
                  data-testid="switch-to-draft-button"
                  disabled={isTransitioning}
                  onClick={() => {
                    setShowSwitchToDraftDialog(true);
                  }}
                  className="inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-400 disabled:hover:bg-gray-50"
                >
                  Switch to draft
                </button>
              )}
              {!isNewWorkflow && isSandbox && (
                <button
                  type="button"
                  data-testid="promote-sandbox-button"
                  onClick={() => {
                    setShowPromoteDialog(true);
                  }}
                  className="inline-flex items-center gap-1 rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-primary-500 disabled:cursor-not-allowed disabled:bg-primary-300 disabled:hover:bg-primary-300"
                >
                  Promote
                </button>
              )}
              {lifecycleState === 'live' && !isSandbox && !isNewWorkflow && (
                <Tooltip
                  content={
                    canProvisionSandbox
                      ? null
                      : 'You do not have permission to create a sandbox in this project.'
                  }
                  side="bottom"
                >
                  <button
                    type="button"
                    data-testid="edit-in-sandbox-button"
                    disabled={!canProvisionSandbox}
                    onClick={() => {
                      if (!canProvisionSandbox) return;
                      setShowEditInSandboxPicker(true);
                    }}
                    className="inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-400 disabled:hover:bg-gray-50"
                  >
                    Edit in sandbox
                  </button>
                </Tooltip>
              )}
              {projectId &&
                workflowId &&
                firstTriggerId &&
                !isNewWorkflow &&
                !isReadOnly && (
                  <NewRunButton
                    onClick={() => {
                      void (isRetryable
                        ? handleRetryClick()
                        : handleRunClick());
                    }}
                    onRunWithCustomInputClick={handleRunWithCustomInputClick}
                    disabled={!canRun || isRunPanelOpen || isIDEOpen}
                    isRunning={isSubmitting || runIsProcessing}
                    text={isRetryable ? 'Run (Retry)' : 'Run'}
                  />
                )}
              {(!isReadOnly || readOnlyReason === 'unsaved_new') && (
                <SaveButton
                  canSave={
                    canSave &&
                    !hasSettingsErrors &&
                    // For new workflows, check based on creation method
                    !(
                      isNewWorkflow &&
                      !isCreateWorkflowPanelCollapsed &&
                      // Template method: need a selected template OR workflow on canvas
                      ((currentMethod === 'template' &&
                        !selectedTemplate &&
                        isWorkflowEmpty) ||
                        // Import method: need valid YAML
                        (currentMethod === 'import' &&
                          importPanelState !== 'valid'))
                    ) &&
                    // When panel is collapsed, just check workflow isn't empty
                    !(
                      isNewWorkflow &&
                      isCreateWorkflowPanelCollapsed &&
                      isWorkflowEmpty
                    )
                  }
                  tooltipMessage={
                    isNewWorkflow &&
                    !isCreateWorkflowPanelCollapsed &&
                    currentMethod === 'import' &&
                    importPanelState === 'invalid'
                      ? 'Fix validation errors to continue'
                      : isNewWorkflow &&
                          !isCreateWorkflowPanelCollapsed &&
                          currentMethod === 'template' &&
                          !selectedTemplate
                        ? 'Select a template to continue'
                        : isNewWorkflow && isWorkflowEmpty
                          ? 'Cannot save an empty workflow'
                          : tooltipMessage
                  }
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
            isOpen={showSwitchToDraftDialog}
            onClose={() => {
              setShowSwitchToDraftDialog(false);
            }}
            onConfirm={() => {
              setShowSwitchToDraftDialog(false);
              setIsTransitioning(true);
              void switchToDraft()
                .catch(() =>
                  notifications.alert({
                    title: 'Could not switch to draft',
                    description: 'Please try again.',
                  })
                )
                .finally(() => {
                  setIsTransitioning(false);
                });
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
