import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/react';
import { useCallback, useMemo } from 'react';

import { useURLState } from '#/react/lib/use-url-state';
import { buildClassicalEditorUrl } from '../../utils/editorUrlConversion';
import {
  useIsNewWorkflow,
  useLatestSnapshotLockVersion,
  useProjectRepoConnection,
} from '../hooks/useSessionContext';
import {
  useImportPanelState,
  useIsCreateWorkflowPanelCollapsed,
  useUICommands,
} from '../hooks/useUI';
import {
  useCanRun,
  useCanSave,
  useNodeSelection,
  useWorkflowActions,
  useWorkflowEnabled,
  useWorkflowSettingsErrors,
  useWorkflowState,
} from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';

import { ActiveCollaborators } from './ActiveCollaborators';
import { AIButton } from './AIButton';
import { Breadcrumbs } from './Breadcrumbs';
import { Button } from './Button';
import { EmailVerificationBanner } from './EmailVerificationBanner';
import { GitHubSyncModal } from './GitHubSyncModal';
import { Switch } from './inputs/Switch';
import { ReadOnlyWarning } from './ReadOnlyWarning';
import { ShortcutKeys } from './ShortcutKeys';
import { Tooltip } from './Tooltip';

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
}: {
  canSave: boolean;
  tooltipMessage: string;
  onClick: () => void;
  repoConnection: ReturnType<typeof useProjectRepoConnection>;
  onSyncClick: () => void;
  label?: string;
}) {
  const hasGitHubIntegration = repoConnection !== null;

  if (!hasGitHubIntegration) {
    return (
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
            disabled:cursor-not-allowed disabled:opacity-50 px-3 py-2
            bg-primary-600 hover:bg-primary-500
            disabled:hover:bg-primary-600 text-white
            focus-visible:outline-2 focus-visible:outline-offset-2
            focus-visible:outline-primary-600 focus:ring-transparent"
            onClick={onClick}
            disabled={!canSave}
          >
            {label}
          </button>
        </Tooltip>
      </div>
    );
  }

  return (
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
          disabled:cursor-not-allowed disabled:opacity-50 px-3 py-2
          bg-primary-600 hover:bg-primary-500
          disabled:hover:bg-primary-600 text-white
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
            disabled:opacity-50 bg-primary-600 hover:bg-primary-500
            disabled:hover:bg-primary-600 text-white
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
                canSave ? (
                  <ShortcutKeys keys={['mod', 'shift', 's']} />
                ) : (
                  tooltipMessage
                )
              }
              side="bottom"
            >
              <button
                type="button"
                onClick={onSyncClick}
                disabled={!canSave}
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
  );
}
SaveButton.displayName = 'SaveButton';

export function Header({
  children,
  projectId,
  workflowId,
  isRunPanelOpen = false,
  isIDEOpen = false,
}: {
  children: React.ReactNode[];
  projectId?: string;
  workflowId?: string;
  isRunPanelOpen?: boolean;
  isIDEOpen?: boolean;
}) {
  // IMPORTANT: All hooks must be called unconditionally before any early returns or conditional logic
  const { params, updateSearchParams } = useURLState();
  const { selectNode } = useNodeSelection();
  const { enabled, setEnabled } = useWorkflowEnabled();
  const { saveWorkflow } = useWorkflowActions();
  const { canSave, tooltipMessage } = useCanSave();
  const triggers = useWorkflowState(state => state.triggers);
  const jobs = useWorkflowState(state => state.jobs);
  const { canRun, tooltipMessage: runTooltipMessage } = useCanRun();
  const { openRunPanel, openGitHubSyncModal } = useUICommands();
  const repoConnection = useProjectRepoConnection();
  const { hasErrors: hasSettingsErrors } = useWorkflowSettingsErrors();
  const workflow = useWorkflowState(state => state.workflow);
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();
  const isNewWorkflow = useIsNewWorkflow();
  const isCreateWorkflowPanelCollapsed = useIsCreateWorkflowPanelCollapsed();
  const importPanelState = useImportPanelState();

  // Derived values after all hooks are called
  const firstTriggerId = triggers[0]?.id;
  const isWorkflowEmpty = jobs.length === 0 && triggers.length === 0;

  const isOldSnapshot =
    workflow !== null &&
    latestSnapshotLockVersion !== null &&
    workflow.lock_version !== latestSnapshotLockVersion;

  const handleRunClick = useCallback(() => {
    if (firstTriggerId) {
      // Canvas context: open run panel with first trigger
      selectNode(firstTriggerId);
      openRunPanel({ triggerId: firstTriggerId });
    }
  }, [firstTriggerId, openRunPanel, selectNode]);

  // Compute Run button tooltip content
  const runButtonTooltip = useMemo(() => {
    if (!canRun) return runTooltipMessage; // Error message
    if (isRunPanelOpen || isIDEOpen) return null; // Shortcut captured by panel
    return <ShortcutKeys keys={['mod', 'enter']} />; // Shortcut applies
  }, [canRun, runTooltipMessage, isRunPanelOpen, isIDEOpen]);

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
    { enabled: canSave && !!repoConnection }
  );

  return (
    <>
      <EmailVerificationBanner />

      <div className="flex-none bg-white shadow-xs border-b border-gray-200 relative z-50">
        <div className="mx-auto sm:px-4 lg:px-4 py-6 flex items-center h-20 text-sm">
          <Breadcrumbs>{children}</Breadcrumbs>
          <ReadOnlyWarning className="ml-3" />
          {projectId && workflowId && (
            <a
              href={buildClassicalEditorUrl({
                projectId,
                workflowId,
                searchParams: new URLSearchParams(params),
                isNewWorkflow,
              })}
              className="inline-flex items-center justify-center
              w-6 h-6 text-primary-600 hover:text-primary-700
              hover:bg-primary-50 rounded transition-colors ml-2"
            >
              <Tooltip
                content={"You're using the new editor — click to switch back."}
                side="bottom"
              >
                <span className="hero-beaker-solid h-4 w-4" />
              </Tooltip>
            </a>
          )}
          <ActiveCollaborators className="ml-2" />
          <div className="grow ml-2"></div>

          <div className="flex flex-row gap-2 items-center">
            <div className="flex flex-row gap-2 items-center">
              {!isOldSnapshot && (
                <Tooltip
                  content={
                    isNewWorkflow && isWorkflowEmpty
                      ? 'Add a workflow to enable'
                      : null
                  }
                  side="bottom"
                >
                  <span className="inline-block">
                    <Switch
                      checked={enabled ?? false}
                      onChange={setEnabled}
                      disabled={isNewWorkflow && isWorkflowEmpty}
                    />
                  </span>
                </Tooltip>
              )}

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
                    className={`w-5 h-5 place-self-center ${
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
              {projectId && workflowId && firstTriggerId && !isNewWorkflow && (
                <Tooltip content={runButtonTooltip} side="bottom">
                  <span className="inline-block">
                    <Button
                      variant="primary"
                      onClick={handleRunClick}
                      disabled={!canRun || isRunPanelOpen || isIDEOpen}
                    >
                      Run
                    </Button>
                  </span>
                </Tooltip>
              )}
              <SaveButton
                canSave={
                  canSave &&
                  !hasSettingsErrors &&
                  !(isNewWorkflow && isWorkflowEmpty) &&
                  // When import panel is open, sync with its validation state
                  !(
                    isNewWorkflow &&
                    !isCreateWorkflowPanelCollapsed &&
                    importPanelState !== 'valid'
                  )
                }
                tooltipMessage={
                  isNewWorkflow &&
                  !isCreateWorkflowPanelCollapsed &&
                  importPanelState === 'invalid'
                    ? 'Fix validation errors to continue'
                    : isNewWorkflow && isWorkflowEmpty
                      ? 'Cannot save an empty workflow'
                      : tooltipMessage
                }
                onClick={() => void saveWorkflow()}
                repoConnection={repoConnection}
                onSyncClick={openGitHubSyncModal}
                label={isNewWorkflow ? 'Create' : 'Save'}
              />
            </div>
          </div>

          <AIButton className="ml-2" />

          <GitHubSyncModal />
        </div>
      </div>
    </>
  );
}
