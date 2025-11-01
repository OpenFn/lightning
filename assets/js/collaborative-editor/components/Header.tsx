import { Menu, MenuButton, MenuItem, MenuItems } from "@headlessui/react";
import { useCallback } from "react";
import { useHotkeys } from "react-hotkeys-hook";

import { useURLState } from "../../react/lib/use-url-state";
import { cn } from "../../utils/cn";
import { buildClassicalEditorUrl } from "../../utils/editorUrlConversion";
import {
  useIsNewWorkflow,
  useLatestSnapshotLockVersion,
  useProjectRepoConnection,
  useUser,
} from "../hooks/useSessionContext";
import { useUICommands } from "../hooks/useUI";
import {
  useCanRun,
  useCanSave,
  useNodeSelection,
  useWorkflowActions,
  useWorkflowEnabled,
  useWorkflowState,
} from "../hooks/useWorkflow";
import { getAvatarInitials } from "../utils/avatar";

import { ActiveCollaborators } from "./ActiveCollaborators";
import { Breadcrumbs } from "./Breadcrumbs";
import { Button } from "./Button";
import { EmailVerificationBanner } from "./EmailVerificationBanner";
import { GitHubSyncModal } from "./GitHubSyncModal";
import { Switch } from "./inputs/Switch";
import { ReadOnlyWarning } from "./ReadOnlyWarning";
import { Tooltip } from "./Tooltip";

const userNavigation = [
  { label: "User Profile", url: "/profile", icon: "hero-user-circle" },
  { label: "Credentials", url: "/credentials", icon: "hero-key" },
  { label: "API Tokens", url: "/profile/tokens", icon: "hero-key" },
  {
    label: "Log out",
    url: "/users/log_out",
    icon: "hero-arrow-right-on-rectangle",
  },
];

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
}: {
  canSave: boolean;
  tooltipMessage: string;
  onClick: () => void;
  repoConnection: ReturnType<typeof useProjectRepoConnection>;
  onSyncClick: () => void;
}) {
  const hasGitHubIntegration = repoConnection !== null;

  if (!hasGitHubIntegration) {
    // Simple save button when no GitHub integration
    return (
      <div className="inline-flex rounded-md shadow-xs z-5">
        <Tooltip content={tooltipMessage} side="bottom">
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
            Save
          </button>
        </Tooltip>
      </div>
    );
  }

  // Split button with dropdown when GitHub integration exists
  return (
    <div className="inline-flex rounded-md shadow-xs z-5">
      <Tooltip content={tooltipMessage} side="bottom">
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
          Save
        </button>
      </Tooltip>
      <Menu as="div" className="relative -ml-px block">
        <Tooltip content={tooltipMessage} side="bottom">
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
        </Tooltip>
        <MenuItems
          transition
          className="absolute right-0 z-10 mt-2 w-max origin-top-right
          rounded-md bg-white py-1 shadow-lg outline outline-black/5
          transition data-closed:scale-95 data-closed:transform
          data-closed:opacity-0 data-enter:duration-200 data-enter:ease-out
          data-leave:duration-75 data-leave:ease-in"
        >
          <MenuItem>
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
          </MenuItem>
        </MenuItems>
      </Menu>
    </div>
  );
}
SaveButton.displayName = "SaveButton";

export function Header({
  children,
  projectId,
  workflowId,
}: {
  children: React.ReactNode[];
  projectId?: string;
  workflowId?: string;
}) {
  // URL state management (needed early for handleRunClick)
  const { updateSearchParams } = useURLState();

  // Node selection
  const { selectNode } = useNodeSelection();

  // Separate queries and commands for proper CQS
  const { enabled, setEnabled } = useWorkflowEnabled();
  const { saveWorkflow } = useWorkflowActions();

  // Get save button state
  const { canSave, tooltipMessage } = useCanSave();

  // Get triggers to check if workflow has any
  const triggers = useWorkflowState(state => state.triggers);
  const firstTriggerId = triggers[0]?.id;

  // Get run button state from hook
  const { canRun, tooltipMessage: runTooltipMessage } = useCanRun();

  // Get UI commands from store
  const { openRunPanel, openGitHubSyncModal } = useUICommands();

  // Get GitHub repo connection for split button
  const repoConnection = useProjectRepoConnection();

  // Detect if viewing old snapshot
  const workflow = useWorkflowState(state => state.workflow);
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();

  const isOldSnapshot =
    workflow !== null &&
    latestSnapshotLockVersion !== null &&
    workflow.lock_version !== latestSnapshotLockVersion;

  const handleRunClick = useCallback(() => {
    if (firstTriggerId) {
      // Select the trigger in the diagram
      selectNode(firstTriggerId);
      // Open the run panel via store
      openRunPanel({ triggerId: firstTriggerId });
    }
  }, [firstTriggerId, openRunPanel, selectNode]);

  // Global save shortcut: Ctrl/Cmd+S
  useHotkeys(
    "ctrl+s,meta+s", // Windows/Linux: Ctrl+S, Mac: Cmd+S
    event => {
      event.preventDefault(); // Always prevent browser's "Save Page" dialog
      if (canSave) {
        saveWorkflow(); // Only save when allowed
      }
    },
    {
      enabled: true, // Always listen to prevent browser save
      enableOnFormTags: true, // Allow in Monaco editor, input fields, textareas
    },
    [saveWorkflow, canSave] // Re-register when dependencies change
  );

  // Global save and sync shortcut: Ctrl/Cmd+Shift+S (only when GitHub integration available)
  useHotkeys(
    "ctrl+shift+s,meta+shift+s", // Windows/Linux: Ctrl+Shift+S, Mac: Cmd+Shift+S
    event => {
      event.preventDefault(); // Prevent any browser shortcuts
      if (canSave && repoConnection) {
        openGitHubSyncModal(); // Open sync modal when allowed and GitHub connected
      }
    },
    {
      enableOnFormTags: true, // Allow in Monaco editor, input fields, textareas
    },
    [openGitHubSyncModal, canSave, repoConnection] // Re-register when dependencies change
  );

  // Session context queries
  const user = useUser();
  const isNewWorkflow = useIsNewWorkflow();

  // Generate avatar initials from user data
  const avatarInitials = getAvatarInitials(user);

  return (
    <>
      <EmailVerificationBanner />

      <div className="flex-none bg-white shadow-xs border-b border-gray-200">
        <div className="mx-auto sm:px-6 lg:px-8 py-6 flex items-center h-20 text-sm">
          <Breadcrumbs>{children}</Breadcrumbs>
          <ReadOnlyWarning className="ml-3" />
          {projectId && workflowId && (
            <a
              href={buildClassicalEditorUrl({
                projectId,
                workflowId: workflowId ?? null,
                searchParams: new URLSearchParams(window.location.search),
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

          <div className="flex flex-row gap-2">
            <div className="flex flex-row m-auto gap-2">
              {!isOldSnapshot && (
                <Switch checked={enabled ?? false} onChange={setEnabled} />
              )}

              <div>
                <button
                  type="button"
                  onClick={() => updateSearchParams({ panel: "settings" })}
                  className="w-5 h-5 place-self-center cursor-pointer
                  text-slate-500 hover:text-slate-400"
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
                <Tooltip content={runTooltipMessage} side="bottom">
                  <span className="inline-block">
                    <Button
                      variant="primary"
                      onClick={handleRunClick}
                      disabled={!canRun}
                    >
                      Run
                    </Button>
                  </span>
                </Tooltip>
              )}
              <SaveButton
                canSave={canSave}
                tooltipMessage={tooltipMessage}
                onClick={saveWorkflow}
                repoConnection={repoConnection}
                onSyncClick={openGitHubSyncModal}
              />
            </div>
          </div>

          <GitHubSyncModal />

          <div className="w-5"></div>
          <Menu as="div" className="relative ml-3">
            <MenuButton
              className="relative flex max-w-xs items-center
            rounded-full focus-visible:outline-2
            focus-visible:outline-offset-2
            focus-visible:outline-indigo-600"
            >
              <span className="absolute -inset-1.5" />
              <span className="sr-only">Open user menu</span>
              <div
                className="inline-flex items-center justify-center
              align-middle"
              >
                <div className="size-8 rounded-full bg-gray-100">
                  <div
                    className="size-full flex items-center
                  justify-center text-sm font-semibold text-gray-500"
                  >
                    {avatarInitials}
                  </div>
                </div>
              </div>
            </MenuButton>

            <MenuItems
              transition
              className="absolute right-0 z-50 mt-2 w-48
              origin-top-right rounded-md bg-white py-1 shadow-lg
              outline outline-black/5 transition data-closed:scale-95
              data-closed:transform data-closed:opacity-0
              data-enter:duration-200 data-enter:ease-out
              data-leave:duration-75 data-leave:ease-in"
            >
              {userNavigation.map(item => (
                <MenuItem key={item.label}>
                  <a
                    href={item.url}
                    className="block px-4 py-2 text-sm text-gray-700
                    data-focus:bg-gray-100 data-focus:outline-hidden"
                  >
                    <span
                      className={cn(
                        item.icon,
                        "w-5 h-5 mr-2 text-secondary-500"
                      )}
                    ></span>
                    {item.label}
                  </a>
                </MenuItem>
              ))}
            </MenuItems>
          </Menu>
        </div>
      </div>
    </>
  );
}
