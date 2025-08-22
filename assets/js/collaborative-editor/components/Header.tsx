import { Menu, MenuButton, MenuItem, MenuItems } from "@headlessui/react";

import { useWorkflowEnabled } from "../hooks/useWorkflow";

import { Breadcrumbs } from "./Breadcrumbs";
import { Switch } from "./inputs/Switch";

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

export function Header({ children }: { children: React.ReactNode[] }) {
  // Separate queries and commands for proper CQS
  const { enabled, setEnabled } = useWorkflowEnabled();

  return (
    <div className="flex-none bg-white shadow-xs border-b border-gray-200">
      <div className="mx-auto sm:px-6 lg:px-8 py-6 flex items-center h-20 text-sm">
        <Breadcrumbs>{children}</Breadcrumbs>

        <div className="grow"></div>

        <div className="flex flex-row gap-2">
          <div className="flex flex-row m-auto gap-2">
            <Switch checked={enabled ?? false} onChange={setEnabled} />

            <div>
              <a
                href="#settings"
                id="toggle-settings"
                className="w-5 h-5 place-self-center cursor-pointer text-slate-500 hover:text-slate-400"
              >
                <span className="hero-adjustments-vertical"></span>
              </a>
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
                phx-click='[["push",{"event":"save"}]]'
                phx-hook="InspectorSaveViaCtrlS"
                phx-disable-with=""
                phx-connected='[["remove_attr",{"attr":"disabled"}]]'
                phx-disconnected='[["set_attr",{"attr":["disabled",""]}]]'
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
                <div className="size-full flex items-center justify-center text-sm font-semibold text-gray-500">
                  AA
                </div>
              </div>
            </div>
          </MenuButton>

          <MenuItems
            transition
            className="absolute right-0 z-10 mt-2 w-48 origin-top-right rounded-md bg-white py-1 shadow-lg outline outline-black/5 transition data-closed:scale-95 data-closed:transform data-closed:opacity-0 data-enter:duration-200 data-enter:ease-out data-leave:duration-75 data-leave:ease-in"
          >
            {userNavigation.map(item => (
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
