import type { Meta, StoryObj } from '@storybook/react-vite';
import type { ButtonHTMLAttributes, ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clones of `LightningWeb.SandboxLive.Components`
 * (lib/lightning_web/live/sandbox_live/components.ex):
 * `header/1`, `create_button/1`, `workspace_list/1`, `confirm_delete_modal/1`,
 * `merge_modal/1` and `color_palette/1`.
 *
 * The delete and merge modals render into the shared
 * `LightningWeb.Components.Modal.modal/1` panel
 * (lib/lightning_web/live/components/modal.ex). Presentational only: every
 * `phx-*` binding, the `.form` plumbing, Tooltip hooks and `JS` transitions are
 * dropped, and the modals are rendered statically open.
 */

// --- Color palette, copied verbatim from @color_palette --------------------
const COLOR_PALETTE = [
  '#870d4c',
  '#E33D63',
  '#E64A2E',
  '#F39B33',
  '#F4C644',
  '#fcde32',
  '#d6e819',
  '#9AD04E',
  '#E040FB',
  '#8E3FB1',
  '#5E3FB8',
  '#5AA1F0',
  '#68d6e2',
  '#4AC1CE',
  '#2E9B92',
  '#56B15A',
];

// --- Themed button, mirroring NewInputs.button/1 ----------------------------
type ButtonTheme = 'primary' | 'secondary' | 'danger';
type ButtonSize = 'md' | 'lg';

const BUTTON_BASE = 'rounded-md text-sm font-semibold shadow-xs cursor-pointer';

const BUTTON_SIZE: Record<ButtonSize, string> = {
  md: 'px-3 py-2',
  lg: 'px-3.5 py-2.5',
};

const BUTTON_THEME: Record<ButtonTheme, string> = {
  primary:
    'bg-primary-600 hover:bg-primary-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600',
  secondary:
    'bg-white hover:bg-gray-50 text-gray-900 ring-1 ring-gray-300 ring-inset',
  danger:
    'bg-red-600 hover:bg-red-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600',
};

const BUTTON_THEME_DISABLED: Record<ButtonTheme, string> = {
  primary: 'bg-primary-300 text-white disabled:cursor-auto',
  secondary:
    'bg-gray-50 text-gray-400 ring-1 ring-gray-200 ring-inset disabled:cursor-auto',
  danger: 'bg-red-300 text-white disabled:cursor-auto',
};

interface LvButtonProps
  extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'type'> {
  theme?: ButtonTheme;
  size?: ButtonSize;
  type?: 'button' | 'submit';
  children: ReactNode;
}

function LvButton({
  theme = 'primary',
  size = 'md',
  type = 'button',
  disabled = false,
  className,
  children,
  ...rest
}: LvButtonProps) {
  return (
    <button
      type={type}
      disabled={disabled}
      className={cn(
        BUTTON_BASE,
        BUTTON_SIZE[size],
        disabled ? BUTTON_THEME_DISABLED[theme] : BUTTON_THEME[theme],
        className
      )}
      {...rest}
    >
      {children}
    </button>
  );
}

// --- Custom "branches" icon, copied from Icon.branches/1 --------------------
function BranchesIcon({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      className={className}
      aria-hidden="true"
    >
      <circle cx="6" cy="6" r="2.25" />
      <circle cx="18" cy="6" r="2.25" />
      <circle cx="18" cy="18" r="2.25" />
      <path d="M6 8v10a4 4 0 0 0 4 4h8" />
      <path d="M8 6h8" />
    </svg>
  );
}

// --- Shared modal scaffolding, mirroring modal.ex ---------------------------
function ModalPanel({
  width = 'max-w-3xl',
  title,
  children,
}: {
  width?: string;
  title: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="flex justify-center rounded-lg bg-gray-100 p-10">
      <div className={width}>
        <div className="relative rounded-xl bg-white py-[24px] shadow-lg shadow-zinc-700/10 ring-1 ring-zinc-700/10">
          <header className="pr-[24px] pl-[24px]">
            <h1 className="text-lg leading-5 font-semibold text-zinc-800">
              {title}
            </h1>
          </header>
          <div className="my-[16px] h-0.5 grow bg-gray-100" />
          <section className="pr-[24px] pl-[24px]">{children}</section>
        </div>
      </div>
    </div>
  );
}

function ModalFooter({ children }: { children: ReactNode }) {
  return (
    <>
      <div className="mt-[16px]" />
      <footer className="gap-3 sm:flex sm:flex-row-reverse">{children}</footer>
    </>
  );
}

function ModalTitleWithClose({ children }: { children: ReactNode }) {
  return (
    <div className="flex items-start justify-between">
      <span className="font-bold">{children}</span>
      <button
        type="button"
        aria-label="Close"
        className="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
      >
        <span className="hero-x-mark size-5" />
      </button>
    </div>
  );
}

// --- Badge, mirroring the private badge/1 -----------------------------------
function Badge({ env }: { env: string }) {
  return (
    <span className="inline-block max-w-32 truncate rounded-full bg-slate-200 px-2 py-1 text-xs text-slate-700">
      {env}
    </span>
  );
}

// --- Mock data --------------------------------------------------------------
interface Sandbox {
  id: string;
  name: string;
  color: string;
  env?: string;
  isCurrent?: boolean;
}

const ROOT_PROJECT = { id: 'root', name: 'Ministry of Health', env: 'main' };

const ACTIVE_SANDBOXES: Sandbox[] = [
  {
    id: 's1',
    name: 'Staging - Q2 rollout',
    color: '#5AA1F0',
    env: 'staging',
    isCurrent: true,
  },
  { id: 's2', name: 'Experiment - new aggregation', color: '#9AD04E' },
  { id: 's3', name: 'Hotfix - CommCare mapping', color: '#E64A2E', env: 'dev' },
];

const SCHEDULED_SANDBOXES: Sandbox[] = [
  { id: 's4', name: 'Old import test', color: '#8E3FB1', env: 'dev' },
];

interface MergeWorkflow {
  id: string;
  name: string;
  state: 'changed' | 'diverged' | 'new' | 'deleted';
  checked: boolean;
}

const MERGE_WORKFLOWS: MergeWorkflow[] = [
  { id: 'w1', name: 'Patient sync', state: 'changed', checked: true },
  { id: 'w2', name: 'DHIS2 export', state: 'diverged', checked: true },
  { id: 'w3', name: 'Kobo intake', state: 'new', checked: false },
  { id: 'w4', name: 'Legacy nightly job', state: 'deleted', checked: false },
];

// --- header/1 + create_button/1 ---------------------------------------------
function SandboxHeader({ disabled = false }: { disabled?: boolean }) {
  return (
    <div className="mb-6 flex items-center justify-between">
      <h3 className="text-3xl font-bold">Sandboxes</h3>
      <LvButton theme="primary" size="lg" disabled={disabled}>
        Create Sandbox
      </LvButton>
    </div>
  );
}

// --- workspace_list/1 sub-cards ---------------------------------------------
function RootProjectCard({
  name,
  env,
  isCurrent,
}: {
  name: string;
  env: string;
  isCurrent?: boolean;
}) {
  return (
    <div className="group block cursor-pointer overflow-hidden rounded-xl border border-gray-200 bg-white transition-all duration-200 hover:bg-gray-50">
      <div className="flex items-stretch">
        <div className="w-3 flex-shrink-0 bg-indigo-600" />
        <div className="flex min-w-0 flex-1 items-center justify-between px-4 py-4">
          <div className="min-w-0 flex-1">
            <div className="mb-1 flex items-center gap-3">
              <h3 className="truncate text-lg font-semibold text-slate-900 group-hover:text-slate-800">
                {name}
              </h3>
              <Badge env={env} />
              {isCurrent ? <Badge env="active" /> : null}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function SandboxActions() {
  return (
    <div className="ml-4 flex flex-shrink-0 gap-1">
      <span className="inline-block">
        <button
          type="button"
          aria-label="Merge this sandbox"
          className="flex items-center justify-center rounded-lg p-2 transition-colors hover:bg-slate-100"
        >
          <BranchesIcon className="h-4 w-4 text-slate-700" />
        </button>
      </span>
      <span className="inline-block">
        <button
          type="button"
          aria-label="Edit this sandbox"
          className="flex items-center justify-center rounded-lg p-2 transition-colors hover:bg-slate-100"
        >
          <span className="hero-pencil-square h-4 w-4 text-slate-700" />
        </button>
      </span>
      <span className="inline-block">
        <button
          type="button"
          aria-label="Delete this sandbox"
          className="flex items-center justify-center rounded-lg p-2 transition-colors hover:bg-slate-100"
        >
          <span className="hero-trash h-4 w-4 text-slate-700" />
        </button>
      </span>
    </div>
  );
}

function SandboxCard({ sandbox }: { sandbox: Sandbox }) {
  return (
    <div className="group block cursor-pointer overflow-hidden rounded-xl border border-gray-200 bg-white transition-all duration-200 hover:bg-gray-50">
      <div className="flex items-stretch">
        <div
          className="w-3 flex-shrink-0"
          style={{ backgroundColor: sandbox.color }}
        />
        <div className="flex min-w-0 flex-1 items-center justify-between px-4 py-4">
          <div className="min-w-0 flex-1">
            <div className="mb-1 flex items-center gap-3">
              <h3 className="truncate text-lg font-semibold text-slate-900 group-hover:text-slate-800">
                {sandbox.name}
              </h3>
              {sandbox.env ? <Badge env={sandbox.env} /> : null}
              {sandbox.isCurrent ? <Badge env="active" /> : null}
            </div>
          </div>
          <SandboxActions />
        </div>
      </div>
    </div>
  );
}

function ScheduledSandboxCard({ sandbox }: { sandbox: Sandbox }) {
  return (
    <div className="group block overflow-hidden rounded-xl border border-gray-200 bg-gray-50 opacity-75">
      <div className="flex items-stretch">
        <div
          className="w-3 flex-shrink-0 opacity-60"
          style={{ backgroundColor: sandbox.color }}
        />
        <div className="flex min-w-0 flex-1 items-center justify-between px-4 py-4">
          <div className="min-w-0 flex-1 cursor-not-allowed">
            <div className="mb-1 flex items-center gap-3">
              <h3 className="truncate text-lg font-semibold text-slate-500 line-through">
                {sandbox.name}
              </h3>
              {sandbox.env ? <Badge env={sandbox.env} /> : null}
            </div>
          </div>
          <div className="ml-4 flex-shrink-0">
            <LvButton theme="secondary">Restore</LvButton>
          </div>
        </div>
      </div>
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Sandbox (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Header: Story = {
  name: 'header / create_button',
  render: () => (
    <Showcase className="min-w-[640px]">
      <Section
        title="header/1"
        description="The Sandboxes page heading with its primary Create Sandbox button."
      >
        <SandboxHeader />
      </Section>
      <Section
        title="create_button/1 (disabled)"
        description="Disabled when the user can't create sandboxes; the tooltip reason is dropped here."
      >
        <SandboxHeader disabled />
      </Section>
    </Showcase>
  ),
};

export const WorkspaceList: Story = {
  name: 'workspace_list',
  render: () => (
    <Showcase className="min-w-[640px]">
      <Section
        title="workspace_list/1"
        description="The root project card followed by active sandbox cards, then a 'Scheduled for deletion' section with line-through cards."
      >
        <div className="space-y-8">
          <div className="space-y-3">
            <RootProjectCard
              name={ROOT_PROJECT.name}
              env={ROOT_PROJECT.env}
              isCurrent={false}
            />
            <div>
              <div className="space-y-3">
                {ACTIVE_SANDBOXES.map(sandbox => (
                  <SandboxCard key={sandbox.id} sandbox={sandbox} />
                ))}
              </div>
            </div>
          </div>

          <div>
            <h2 className="mb-3 text-2xl font-bold text-slate-900">
              Scheduled for deletion
            </h2>
            <div className="space-y-3">
              {SCHEDULED_SANDBOXES.map(sandbox => (
                <ScheduledSandboxCard key={sandbox.id} sandbox={sandbox} />
              ))}
            </div>
          </div>
        </div>
      </Section>

      <Section
        title="workspace_list/1 (empty)"
        description="Shown when a project has no sandboxes yet."
      >
        <div className="space-y-3">
          <RootProjectCard
            name={ROOT_PROJECT.name}
            env={ROOT_PROJECT.env}
            isCurrent
          />
          <div>
            <div className="rounded-lg border-2 border-dashed border-gray-200 py-8 text-center text-gray-500">
              <div className="space-y-3">
                <div className="text-base font-medium">No sandboxes found</div>
                <div className="text-sm">
                  <a
                    href="#new-sandbox"
                    className="font-medium text-blue-600 hover:text-blue-800"
                  >
                    Create your first sandbox
                  </a>{' '}
                  to start experimenting.
                </div>
              </div>
            </div>
          </div>
        </div>
      </Section>
    </Showcase>
  ),
};

export const ConfirmDeleteModal: Story = {
  name: 'confirm_delete_modal',
  render: () => (
    <Showcase>
      <Section
        title="confirm_delete_modal/1"
        description="Type-to-confirm deletion. The amber notice describes the restore window; the Delete button is disabled until the name matches."
      >
        <ModalPanel
          width="max-w-md"
          title={<ModalTitleWithClose>Delete sandbox</ModalTitleWithClose>}
        >
          <section className="space-y-4">
            <p className="text-gray-700">
              Deleting a sandbox removes it from OpenFn. Its 2 child sandboxes
              will also be deleted.
            </p>
            <p className="text-gray-700">
              Workflows, triggers, versions, keychain clones, and dataclips will
              be permanently removed.
            </p>
            <p className="text-gray-700">
              You are currently viewing this project. After deletion, you'll be
              redirected to <strong>Ministry of Health</strong>.
            </p>
            <p className="text-gray-700">
              To confirm, type the sandbox name below.
            </p>
            <div className="rounded-md border border-amber-200 bg-amber-50 p-3">
              <p className="text-sm text-amber-800">
                This sandbox will be retained for 7 days before being
                permanently removed. You can restore it from the sandbox list
                during that window.
              </p>
            </div>
            <div>
              <label
                htmlFor="confirm-delete-name-input"
                className="mb-2 text-sm/6 font-medium text-slate-800"
              >
                Sandbox name
                <span className="text-red-500"> *</span>
              </label>
              <div>
                <input
                  type="text"
                  id="confirm-delete-name-input"
                  name="confirm[name]"
                  autoComplete="off"
                  placeholder="Staging - Q2 rollout"
                  className="block w-full rounded-lg border-slate-300 text-slate-900 focus:border-slate-400 focus:ring-0 focus:outline focus:outline-2 focus:outline-offset-1 focus:outline-primary-600 sm:text-sm sm:leading-6"
                />
              </div>
            </div>
            <ModalFooter>
              <LvButton theme="danger" type="submit" disabled>
                Delete sandbox
              </LvButton>
              <LvButton theme="secondary">Cancel</LvButton>
            </ModalFooter>
          </section>
        </ModalPanel>
      </Section>
    </Showcase>
  ),
};

export const MergeModal: Story = {
  name: 'merge_modal',
  render: () => (
    <Showcase>
      <Section
        title="merge_modal/1"
        description="Choose a target project and the workflows/credentials to overwrite. Each workflow shows its merge state, and a warning notes the sandbox is deleted after merging."
      >
        <ModalPanel
          width="max-w-xl"
          title={<ModalTitleWithClose>Merge sandbox</ModalTitleWithClose>}
        >
          <section className="space-y-5">
            <div className="space-y-2">
              <div className="flex items-center gap-2 text-sm text-gray-700">
                <span>Merge</span>
                <span className="rounded-md bg-gray-100 px-2 py-0.5 text-sm font-medium text-gray-900">
                  Staging - Q2 rollout
                </span>
                <span>into</span>
                <div className="max-w-[260px] flex-1">
                  <select
                    id="merge-target-select"
                    name="merge[target_id]"
                    aria-label="Merge target"
                    className="block w-full rounded-lg border-slate-300 text-sm text-slate-900 focus:border-slate-400 focus:ring-0 sm:leading-6"
                  >
                    <option>Ministry of Health (main)</option>
                    <option>Hotfix - CommCare mapping</option>
                  </select>
                </div>
              </div>
              <p className="text-sm text-gray-700">
                The workflows you select below will overwrite their counterparts
                in{' '}
                <strong className="font-medium text-gray-900">
                  Ministry of Health
                </strong>
                . Any conflicting changes in the target are lost.
              </p>
            </div>

            <div className="overflow-hidden rounded-lg border border-gray-200 bg-white">
              <label className="flex cursor-pointer items-center gap-3 border-b border-gray-200 bg-gray-50 px-3 py-2">
                <input
                  type="checkbox"
                  aria-label="Select all workflows"
                  className="h-4 w-4 rounded border-gray-300 text-indigo-600"
                />
                <span className="flex-1 text-sm font-medium text-gray-900">
                  Workflows to merge
                </span>
                <span className="text-xs text-gray-500">2 of 4 selected</span>
              </label>
              <ul className="max-h-48 divide-y divide-gray-100 overflow-y-auto">
                {MERGE_WORKFLOWS.map(wf => (
                  <li
                    key={wf.id}
                    className="flex cursor-pointer items-center gap-3 px-3 py-2 hover:bg-gray-50"
                  >
                    <input
                      type="checkbox"
                      readOnly
                      checked={wf.checked}
                      aria-label={`Select ${wf.name}`}
                      className="h-4 w-4 rounded border-gray-300 text-indigo-600"
                    />
                    <span className="flex-1 truncate text-sm text-gray-700">
                      {wf.name}
                    </span>
                    {wf.state === 'changed' ? (
                      <span className="flex items-center gap-1 text-xs font-medium text-green-700">
                        Changed
                      </span>
                    ) : null}
                    {wf.state === 'diverged' ? (
                      <span className="flex items-center gap-1 text-xs font-medium text-amber-700">
                        <span className="hero-exclamation-triangle-mini h-3.5 w-3.5" />
                        Diverged
                      </span>
                    ) : null}
                    {wf.state === 'new' ? (
                      <span className="flex items-center gap-1 text-xs font-medium text-blue-700">
                        New
                      </span>
                    ) : null}
                    {wf.state === 'deleted' ? (
                      <span className="flex items-center gap-1 text-xs font-medium text-red-700">
                        Deleted in sandbox
                      </span>
                    ) : null}
                  </li>
                ))}
              </ul>
            </div>

            <div className="overflow-hidden rounded-lg border border-gray-200 bg-white">
              <label className="flex cursor-pointer items-center gap-3 border-b border-gray-200 bg-gray-50 px-3 py-2">
                <input
                  type="checkbox"
                  aria-label="Select all credentials"
                  className="h-4 w-4 rounded border-gray-300 text-indigo-600"
                />
                <span className="flex-1 text-sm font-medium text-gray-900">
                  Credentials to add
                </span>
                <span className="text-xs text-gray-500">1 of 2 selected</span>
              </label>
              <ul className="max-h-48 divide-y divide-gray-100 overflow-y-auto">
                <li className="flex cursor-pointer items-center gap-3 px-3 py-2 hover:bg-gray-50">
                  <input
                    type="checkbox"
                    readOnly
                    checked
                    aria-label="Select DHIS2 production"
                    className="h-4 w-4 rounded border-gray-300 text-indigo-600"
                  />
                  <span className="flex-1 truncate text-sm text-gray-700">
                    DHIS2 production
                  </span>
                </li>
                <li className="flex cursor-pointer items-center gap-3 px-3 py-2 hover:bg-gray-50">
                  <input
                    type="checkbox"
                    readOnly
                    aria-label="Select CommCare API"
                    className="h-4 w-4 rounded border-gray-300 text-indigo-600"
                  />
                  <span className="flex-1 truncate text-sm text-gray-700">
                    CommCare API
                  </span>
                </li>
              </ul>
            </div>

            <div className="rounded-md bg-yellow-50 p-4 text-wrap">
              <div className="flex items-start">
                <div className="shrink-0">
                  <span className="hero-exclamation-triangle block h-5 w-5 text-yellow-400" />
                </div>
                <div className="ml-3 min-w-0 flex-1">
                  <h3 className="text-sm font-medium text-yellow-800">
                    This sandbox will be deleted after merging
                  </h3>
                  <div className="mt-2 text-sm text-yellow-700">
                    It can be restored from the sandbox list for 7 days, then
                    permanently removed.
                    <div className="mt-2">
                      Its 2 child sandboxes will also be deleted.
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <ModalFooter>
              <LvButton theme="primary" type="submit">
                Merge
              </LvButton>
              <LvButton theme="secondary">Cancel</LvButton>
            </ModalFooter>
          </section>
        </ModalPanel>
      </Section>
    </Showcase>
  ),
};

export const ColorPalette: Story = {
  name: 'color_palette',
  render: () => (
    <Showcase>
      <Section
        title="color_palette/1"
        description="A radio grid of the 16 preset sandbox colors. The selected swatch shows a white check."
      >
        <fieldset>
          <span className="mb-2 block text-sm font-medium text-slate-800">
            Color
          </span>
          <div className="space-y-3">
            <div
              role="radiogroup"
              aria-label="Choose a color for your sandbox"
              className="grid w-fit grid-cols-4 gap-0.5 select-none sm:grid-cols-8"
            >
              {COLOR_PALETTE.map((hex, index) => {
                const selected = index === 0;
                return (
                  <label
                    key={hex}
                    className="group relative inline-block cursor-pointer"
                  >
                    <input
                      type="radio"
                      name="sandbox_color"
                      value={hex}
                      defaultChecked={selected}
                      aria-label={hex}
                      className="sr-only"
                    />
                    <span
                      className="relative block h-12 w-12 rounded-xs transition-all duration-200 group-hover:z-10 group-hover:scale-102 md:h-14 md:w-14"
                      style={{ backgroundColor: hex }}
                      aria-hidden="true"
                    />
                    {selected ? (
                      <span className="pointer-events-none absolute inset-0 z-10 flex items-center justify-center">
                        <span className="hero-check h-5 w-5 text-white drop-shadow-lg sm:h-6 sm:w-6" />
                      </span>
                    ) : null}
                  </label>
                );
              })}
            </div>
          </div>
          <p className="sr-only" aria-live="polite">
            Selected: {COLOR_PALETTE[0]}
          </p>
        </fieldset>
      </Section>
    </Showcase>
  ),
};
