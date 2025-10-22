import { Menu, MenuButton, MenuItem, MenuItems } from "@headlessui/react";
import { useHotkeys } from "react-hotkeys-hook";

import { useURLState } from "../../react/lib/use-url-state";
import { useIsNewWorkflow, useUser } from "../hooks/useSessionContext";
import {
  useCanSave,
  useWorkflowActions,
  useWorkflowEnabled,
} from "../hooks/useWorkflow";
import { getAvatarInitials } from "../utils/avatar";

import { Breadcrumbs } from "./Breadcrumbs";
import { EmailVerificationBanner } from "./EmailVerificationBanner";
import { Switch } from "./inputs/Switch";
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
 * Run button component - visible in React DevTools
 * Uses Phoenix LiveView patch navigation
 */
function RunButton({
  projectId,
  workflowId,
}: {
  projectId: string;
  workflowId: string;
}) {
  return (
    <a
      href={`/projects/${projectId}/w/${workflowId}?m=workflow_input&s=cae544ab-03dc-4ccc-a09c-fb4edb255d7a`}
      data-phx-link="patch"
      data-phx-link-state="push"
      type="button"
      className="rounded-md text-sm font-semibold shadow-xs
      phx-submit-loading:opacity-75 inline-block px-3 py-2
      bg-primary-600 hover:bg-primary-500 text-white
      focus-visible:outline-2 focus-visible:outline-offset-2
      focus-visible:outline-primary-600"
    >
      Run
    </a>
  );
}
RunButton.displayName = "RunButton";

/**
 * Save button component - visible in React DevTools
 * Includes Radix tooltip with save status messaging
 */
function SaveButton({
  canSave,
  tooltipMessage,
  onClick,
}: {
  canSave: boolean;
  tooltipMessage: string;
  onClick: () => void;
}) {
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
  // Separate queries and commands for proper CQS
  const { enabled, setEnabled } = useWorkflowEnabled();
  const { saveWorkflow } = useWorkflowActions();

  // Get save button state
  const { canSave, tooltipMessage } = useCanSave();

  // Global save shortcut: Ctrl/Cmd+S
  useHotkeys(
    "ctrl+s,meta+s", // Windows/Linux: Ctrl+S, Mac: Cmd+S
    (event) => {
      event.preventDefault(); // Always prevent browser's "Save Page" dialog
      if (canSave) {
        saveWorkflow(); // Only save when allowed
      }
    },
    {
      enabled: true, // Always listen to prevent browser save
      scopes: ["global"], // Active everywhere in collaborative editor
      enableOnFormTags: true, // Allow in Monaco editor, input fields, textareas
    },
    [saveWorkflow, canSave] // Re-register when dependencies change
  );

  // Session context queries
  const user = useUser();
  const isNewWorkflow = useIsNewWorkflow();

  // URL state management
  const { updateHash } = useURLState();

  // Generate avatar initials from user data
  const avatarInitials = getAvatarInitials(user);

  return (
    <>
      <EmailVerificationBanner />
      <div className="flex-none bg-white shadow-xs border-b border-gray-200">
        <div className="mx-auto sm:px-6 lg:px-8 py-6 flex items-center h-20 text-sm">
          <Breadcrumbs>{children}</Breadcrumbs>

          {projectId && workflowId && (
            <a
              href={
                isNewWorkflow
                  ? `/projects/${projectId}/w/new`
                  : `/projects/${projectId}/w/${workflowId}`
              }
              className="inline-flex items-center justify-center
              w-6 h-6 text-primary-600 hover:text-primary-700
              hover:bg-primary-50 rounded transition-colors ml-4"
            >
              <Tooltip
                content={"You're using the new editor — click to switch back."}
                side="bottom"
              >
                <span className="hero-beaker-solid h-4 w-4" />
              </Tooltip>
            </a>
          )}

          <div className="grow"></div>

          <div className="flex flex-row gap-2">
            <div className="flex flex-row m-auto gap-2">
              <Switch checked={enabled ?? false} onChange={setEnabled} />

              <div>
                <button
                  type="button"
                  onClick={() => updateHash("settings")}
                  className="w-5 h-5 place-self-center cursor-pointer
                  text-slate-500 hover:text-slate-400"
                >
                  <span className="hero-adjustments-vertical"></span>
                </button>
              </div>
            </div>
            <div
              className="hidden"
              phx-disconnected='[["show",{"transition":[["fade-in"],[],[]]}]]'
              phx-connected='[["hide",{"transition":[["fade-out"],[],[]]}]]'
            >
              <span className="hero-signal-slash w-6 h-6 mr-2 text-red-500"></span>
            </div>
            <div className="relative">
              {projectId && workflowId && (
                <RunButton projectId={projectId} workflowId={workflowId} />
              )}
              <SaveButton
                canSave={canSave}
                tooltipMessage={tooltipMessage}
                onClick={saveWorkflow}
              />
            </div>
          </div>

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
              className="absolute right-0 z-10 mt-2 w-48
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
                      className={`${item.icon} w-5 h-5 mr-2
                      text-secondary-500`}
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
