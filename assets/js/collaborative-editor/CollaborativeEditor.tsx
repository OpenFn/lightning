import { Menu, MenuButton, MenuItem, MenuItems } from "@headlessui/react";
import { useMemo } from "react";
import { SocketProvider } from "../react/contexts/SocketProvider";
import type { WithActionProps } from "../react/lib/with-props";
import {
  BreadcrumbLink,
  Breadcrumbs,
  BreadcrumbText,
} from "./components/Breadcrumbs";
import { CollaborationWidget } from "./components/CollaborationWidget";
import { WorkflowEditor } from "./components/WorkflowEditor";
import { SessionProvider } from "./contexts/SessionProvider";
import { WorkflowStoreProvider } from "./contexts/WorkflowStoreProvider";
import type { CollaborativeEditorDataProps } from "./types/workflow";

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

function Header({ children }: { children: React.ReactNode[] }) {
  return (
    <div className="flex-none bg-white shadow-xs border-b border-gray-200">
      <div className="max-w-7xl mx-auto sm:px-6 lg:px-8 py-6 flex items-center h-20 text-sm">
        <Breadcrumbs>{children}</Breadcrumbs>

        <div className="grow"></div>

        <div className="flex flex-row gap-2">
          <div className="flex flex-row m-auto gap-2">
            <div
              id="toggle-container-workflow"
              className="flex flex-col gap-1 "
              phx-hook="Tooltip"
              aria-label="This workflow is active (webhook trigger enabled)"
            >
              <div
                id="toggle-control-workflow"
                className="flex items-center gap-3"
                phx-click="[[&quot;push&quot;,{&quot;value&quot;:{&quot;value_key&quot;:&quot;&quot;,&quot;_target&quot;:&quot;workflow_state&quot;,&quot;workflow_state&quot;:false},&quot;event&quot;:&quot;toggle_workflow_state&quot;}]]"
              >
                <label className="relative inline-flex items-center cursor-pointer">
                  <input type="hidden" name="workflow_state" value="false" />
                  <input
                    type="checkbox"
                    id="workflow"
                    name="workflow_state"
                    value="true"
                    className="sr-only peer"
                    checked=""
                  />

                  <div
                    tabindex="0"
                    role="switch"
                    aria-checked=""
                    className="relative inline-flex w-11 h-6 rounded-full transition-colors duration-200 ease-in-out border-2 border-transparent focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 bg-indigo-600 cursor-pointer"
                  >
                    <span className="pointer-events-none absolute h-5 w-5 inline-block transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out translate-x-5">
                      <span
                        className="absolute inset-0 flex h-full w-full items-center justify-center transition-opacity duration-200 ease-in opacity-0"
                        aria-hidden="true"
                      >
                        <span className="hero-x-mark-micro h-4 w-4 text-gray-400"></span>
                      </span>
                      <span
                        className="absolute inset-0 flex h-full w-full items-center justify-center transition-opacity duration-200 ease-in opacity-100"
                        aria-hidden="true"
                      >
                        <span className="hero-check-micro h-4 w-4 text-indigo-600"></span>
                      </span>
                    </span>
                  </div>
                </label>
              </div>
            </div>
            <div>
              <a
                href="/projects/4adf2644-ed4e-4f97-a24c-ab35b3cb1efa/w/2356a807-f8db-4097-b474-f37579fd0898?m=settings"
                data-phx-link="patch"
                data-phx-link-state="push"
                id="toggle-settings"
                className="w-5 h-5 place-self-center cursor-pointer text-slate-500 hover:text-slate-400"
              >
                <span className="hero-adjustments-vertical"></span>
              </a>
            </div>
          </div>
          <div
            className="hidden"
            phx-disconnected="[[&quot;show&quot;,{&quot;transition&quot;:[[&quot;fade-in&quot;],[],[]]}]]"
            phx-connected="[[&quot;hide&quot;,{&quot;transition&quot;:[[&quot;fade-out&quot;],[],[]]}]]"
          >
            <span className="hero-signal-slash w-6 h-6 mr-2 text-red-500"></span>
          </div>
          <div className="relative">
            <a
              href="/projects/4adf2644-ed4e-4f97-a24c-ab35b3cb1efa/w/2356a807-f8db-4097-b474-f37579fd0898?m=workflow_input&amp;s=cae544ab-03dc-4ccc-a09c-fb4edb255d7a"
              data-phx-link="patch"
              data-phx-link-state="push"
              type="button"
              className="rounded-md text-sm font-semibold shadow-xs phx-submit-loading:opacity-75 inline-block px-3 py-2 bg-primary-600 hover:bg-primary-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600 "
            >
              Run
            </a>

            <div className="inline-flex rounded-md shadow-xs z-5">
              <button
                id="top-bar-save-workflow-btn"
                type="button"
                className="rounded-md text-sm font-semibold shadow-xs phx-submit-loading:opacity-75 cursor-pointer disabled:cursor-auto px-3 py-2 bg-primary-600 hover:bg-primary-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600 focus:ring-transparent"
                phx-click="[[&quot;push&quot;,{&quot;event&quot;:&quot;save&quot;}]]"
                phx-hook="InspectorSaveViaCtrlS"
                phx-disable-with=""
                phx-connected="[[&quot;remove_attr&quot;,{&quot;attr&quot;:&quot;disabled&quot;}]]"
                phx-disconnected="[[&quot;set_attr&quot;,{&quot;attr&quot;:[&quot;disabled&quot;,&quot;&quot;]}]]"
              >
                Save
              </button>
            </div>
          </div>
        </div>

        <div className="w-5"></div>
        <Menu as="div" className="relative ml-3">
          <MenuButton className="relative flex max-w-xs items-center rounded-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600">
            <span className="absolute -inset-1.5" />
            <span className="sr-only">Open user menu</span>
            <div className="inline-flex items-center justify-center align-middle">
              <div className="size-8 rounded-full bg-gray-100">
                <div className="size-full flex items-center justify-center text-sm text-gray-500">
                  AA
                </div>
              </div>
            </div>
          </MenuButton>

          <MenuItems
            transition
            className="absolute right-0 z-10 mt-2 w-48 origin-top-right rounded-md bg-white py-1 shadow-lg outline outline-black/5 transition data-closed:scale-95 data-closed:transform data-closed:opacity-0 data-enter:duration-200 data-enter:ease-out data-leave:duration-75 data-leave:ease-in"
          >
            {userNavigation.map((item) => (
              <MenuItem key={item.label}>
                <a
                  href={item.url}
                  className="block px-4 py-2 text-sm text-gray-700 data-focus:bg-gray-100 data-focus:outline-hidden"
                >
                  <span
                    className={`${item.icon} w-5 h-5 mr-2 text-secondary-500`}
                  ></span>
                  {item.label}
                </a>
              </MenuItem>
            ))}
          </MenuItems>
        </Menu>
      </div>
    </div>
  );
}

export const CollaborativeEditor: WithActionProps<
  CollaborativeEditorDataProps
> = (props) => {
  // Extract data from props (ReactComponent hook passes data attributes as props)
  const workflowId = props["data-workflow-id"];
  const workflowName = props["data-workflow-name"];
  const userId = props["data-user-id"];
  const userName = props["data-user-name"];
  const projectId = props["data-project-id"];
  const projectName = props["data-project-name"];

  const breadcrumbElements = useMemo(() => {
    return [
      <BreadcrumbLink href="/" icon="hero-home-mini" key="home">
        Home
      </BreadcrumbLink>,
      <BreadcrumbLink href="/projects" key="projects">
        Projects
      </BreadcrumbLink>,
      <BreadcrumbLink href={`/projects/${projectId}`} key="project">
        {projectName}
      </BreadcrumbLink>,
      <BreadcrumbLink href={`/projects/${projectId}/w`} key="workflows">
        Workflows
      </BreadcrumbLink>,
      <div key="workflow" className="flex items-center gap-2">
        <BreadcrumbText>{workflowName}</BreadcrumbText>
        <div
          id="canvas-workflow-version-container"
          className="flex items-middle text-sm font-normal"
        >
          <span
            id="canvas-workflow-version"
            className="inline-flex items-center rounded-md px-1.5 py-0.5 text-xs font-medium bg-blue-100 text-blue-800"
            title="This is the latest version of this workflow"
          >
            latest
          </span>
        </div>
      </div>,
    ];
  }, [projectId, projectName, workflowName]);

  return (
    <div className="collaborative-editor h-full">
      <Header>{breadcrumbElements}</Header>
      <SocketProvider>
        <SessionProvider
          workflowId={workflowId}
          userId={userId}
          userName={userName}
        >
          {/* New WorkflowStoreProvider for workflow editing */}
          <WorkflowStoreProvider>
            <div className="h-full overflow-y-auto">
              <WorkflowEditor />
              <CollaborationWidget />
            </div>
          </WorkflowStoreProvider>
        </SessionProvider>
      </SocketProvider>
    </div>
  );
};
