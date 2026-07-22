import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/react';
import { useCallback, useContext, useState } from 'react';

import { useURLState } from '#/react/lib/use-url-state';

import { Tooltip } from '../../components/Tooltip';
import * as dataclipApi from '../api/dataclips';
import { StoreContext } from '../contexts/StoreProvider';
import { useActiveRun } from '../hooks/useHistory';
import {
  useLimits,
  useProjectRepoConnection,
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
import { notifications } from '../lib/notifications';
import { isFinalState } from '../types/history';

import { ActiveCollaborators } from './ActiveCollaborators';
import { AIButton } from './AIButton';
import { Breadcrumbs } from './Breadcrumbs';
import { EmailVerificationBanner } from './EmailVerificationBanner';
import { GitHubSyncModal } from './GitHubSyncModal';
import { Switch } from './inputs/Switch';
import { NewRunButton } from './NewRunButton';
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
  isRunPanelOpen = false,
  isIDEOpen = false,
  aiAssistantEnabled = false,
}: {
  children: React.ReactNode[];
  projectId?: string;
  workflowId?: string;
  isRunPanelOpen?: boolean;
  isIDEOpen?: boolean;
  aiAssistantEnabled?: boolean;
}) {
  // IMPORTANT: All hooks must be called unconditionally before any early returns or conditional logic
  const { params, updateSearchParams } = useURLState();
  const { selectNode } = useNodeSelection();
  const { enabled, setEnabled } = useWorkflowEnabled();
  const { saveWorkflow } = useWorkflowActions();
  const { canSave, tooltipMessage } = useCanSave();
  const triggers = useWorkflowState(state => state.triggers);
  const { canRun } = useCanRun();
  const { openRunPanel, openGitHubSyncModal } = useUICommands();
  const repoConnection = useProjectRepoConnection();
  const { hasErrors: hasSettingsErrors } = useWorkflowSettingsErrors();
  const limits = useLimits();
  const { isReadOnly } = useWorkflowReadOnly();
  const { hasChanges } = useUnsavedChanges();
  const storeContext = useContext(StoreContext);
  const getLimits = storeContext?.sessionContextStore.getLimits;
  const [isSubmitting, setIsSubmitting] = useState(false);
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

  // Check if viewing a pinned version via URL parameter
  // When ?v= is present, user is viewing a specific version (even if latest)
  const isPinnedVersion = params['v'] !== undefined && params['v'] !== null;

  // Determine AI button disabled message based on priority
  const aiButtonDisabledMessage = !aiAssistantEnabled
    ? 'Your instance does not have build-time AI enabled. Contact your administrator or support@openfn.org to configure it.'
    : isPinnedVersion
      ? 'Switch to the latest version of this workflow to use the AI Assistant.'
      : undefined;

  const showChangeIndicator = hasChanges && canSave;

  const handleRunClick = useCallback(async () => {
    if (!firstTriggerId || !projectId || !workflowId) return;

    setIsSubmitting(true);
    try {
      await saveWorkflow({ notify: 'none' });
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
      await saveWorkflow({ notify: 'none' });

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
          <Breadcrumbs>{children}</Breadcrumbs>
          <ReadOnlyWarning className="ml-3" />
          <ActiveCollaborators className="ml-2" />
          <div className="grow ml-2"></div>

          <div className="flex flex-row gap-2 items-center">
            <div className="flex flex-row gap-2 items-center">
              {!isPinnedVersion && (
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
              {projectId && workflowId && firstTriggerId && (
                <NewRunButton
                  onClick={() => {
                    void (isRetryable ? handleRetryClick() : handleRunClick());
                  }}
                  onRunWithCustomInputClick={handleRunWithCustomInputClick}
                  disabled={!canRun || isRunPanelOpen || isIDEOpen}
                  isRunning={isSubmitting || runIsProcessing}
                  text={isRetryable ? 'Run (Retry)' : 'Run'}
                />
              )}
              <SaveButton
                canSave={canSave && !hasSettingsErrors}
                tooltipMessage={tooltipMessage}
                onClick={() => void saveWorkflow()}
                repoConnection={repoConnection}
                onSyncClick={openGitHubSyncModal}
                label="Save"
                canSync={githubSyncLimit.allowed}
                syncTooltipMessage={githubSyncLimit.message}
                hasChanges={showChangeIndicator}
              />
            </div>
          </div>

          <AIButton
            className="ml-2"
            disabled={isPinnedVersion || !aiAssistantEnabled}
            disabledMessage={aiButtonDisabledMessage}
          />

          <GitHubSyncModal />
        </div>
      </div>
    </>
  );
}
