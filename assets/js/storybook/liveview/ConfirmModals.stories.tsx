import type { Meta, StoryObj } from '@storybook/react-vite';
import type { ButtonHTMLAttributes, ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clones of Lightning's deletion/confirmation LiveComponents, each shown
 * in its open state:
 *
 *   * `LightningWeb.Components.CredentialDeletionModal.render/1`
 *     (lib/lightning_web/live/components/credential_deletion_modal.ex)
 *   * `LightningWeb.Components.ProjectDeletionModal.render/1`
 *     (lib/lightning_web/live/components/project_deletion_modal.ex)
 *   * `LightningWeb.Components.TokenDeletionModal.render/1`
 *     (lib/lightning_web/live/components/token_deletion_modal.ex)
 *   * `LightningWeb.Components.UserDeletionModal.render/1`
 *     (lib/lightning_web/live/components/user_deletion_modal.ex)
 *
 * Each renders into the shared `LightningWeb.Components.Modal.modal/1` panel
 * (lib/lightning_web/live/components/modal.ex). Presentational only: the
 * `phx-*` bindings, `.form` validation and `JS` transitions are dropped and the
 * dialogs are rendered statically open.
 */

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

// Title row with a close (X) button, used by most of the deletion modals.
function ModalTitleWithClose({ children }: { children: ReactNode }) {
  return (
    <div className="flex justify-between">
      <span className="font-bold">{children}</span>
      <button
        type="button"
        aria-label="close"
        className="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
      >
        <span className="sr-only">Close</span>
        <span className="hero-x-mark size-5 stroke-current" />
      </button>
    </div>
  );
}

// --- Themed button, mirroring NewInputs.button/1 ----------------------------
type ButtonTheme = 'primary' | 'secondary' | 'danger';

const BUTTON_BASE = 'rounded-md text-sm font-semibold shadow-xs cursor-pointer';

const BUTTON_THEME: Record<ButtonTheme, string> = {
  primary:
    'bg-primary-600 hover:bg-primary-500 text-white px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600',
  secondary:
    'bg-white hover:bg-gray-50 text-gray-900 ring-1 ring-gray-300 ring-inset px-3 py-2',
  danger:
    'bg-red-600 hover:bg-red-500 text-white px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600',
};

const BUTTON_THEME_DISABLED: Record<ButtonTheme, string> = {
  primary: 'bg-primary-300 text-white px-3 py-2 disabled:cursor-auto',
  secondary:
    'bg-gray-50 text-gray-400 ring-1 ring-gray-200 ring-inset px-3 py-2 disabled:cursor-auto',
  danger: 'bg-red-300 text-white px-3 py-2 disabled:cursor-auto',
};

interface LvButtonProps
  extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'type'> {
  theme?: ButtonTheme;
  type?: 'button' | 'submit';
  children: ReactNode;
}

function LvButton({
  theme = 'primary',
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
        disabled ? BUTTON_THEME_DISABLED[theme] : BUTTON_THEME[theme],
        className
      )}
      {...rest}
    >
      {children}
    </button>
  );
}

// --- Text input, mirroring NewInputs.input/1 (text) -------------------------
function LvTextInput({
  id,
  label,
  placeholder,
  required = false,
}: {
  id: string;
  label: string;
  placeholder?: string;
  required?: boolean;
}) {
  return (
    <div>
      <label htmlFor={id} className="mb-2 text-sm/6 font-medium text-slate-800">
        {label}
        {required ? <span className="text-red-500"> *</span> : null}
      </label>
      <div>
        <input
          type="text"
          id={id}
          name={id}
          autoComplete="off"
          placeholder={placeholder}
          className="block w-full rounded-lg border-slate-300 text-slate-900 focus:border-slate-400 focus:ring-0 focus:outline focus:outline-2 focus:outline-offset-1 focus:outline-primary-600 sm:text-sm sm:leading-6"
        />
      </div>
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Confirm Modals (LiveView Clone)',
  tags: ['redundant'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const CredentialDeletion: Story = {
  name: 'Credential deletion',
  render: () => (
    <Showcase>
      <Section
        title="CredentialDeletionModal.render/1"
        description="Shown when deleting a credential. The italic note appears when the credential still has activity in a project's audit trail."
      >
        <ModalPanel width="max-w-md" title="Delete credential">
          <div className="text-sm text-gray-500">
            <p>
              Deleting this credential will immediately remove it from all jobs
              and projects. If you later restore it, you will need to re-share it
              with projects and re-associate it with jobs. Are you sure you'd
              like to delete the credential?
            </p>
            <p className="mt-2 text-slate-500 italic">
              *This credential has been used in workflow runs that are still
              monitored in at least one project's audit trail. The credential
              will be made unavailable for future use immediately and after a
              cooling-off period all secrets will be permanently scrubbed, but
              the record itself will not be removed until related workflow runs
              have been purged.
            </p>
          </div>
          <ModalFooter>
            <LvButton theme="danger">Delete credential</LvButton>
            <LvButton theme="secondary">Cancel</LvButton>
          </ModalFooter>
        </ModalPanel>
      </Section>

      <Section
        title="Marked for deletion (delete_now? + has_activity)"
        description="The acknowledgement variant when the credential is already scheduled for deletion but still tied to audited runs."
      >
        <ModalPanel title="Credential marked for deletion">
          <div className="text-sm text-gray-500">
            <p>
              This credential has been used in workflow runs that are still
              monitored in at least one project's audit trail. The credential
              will be made unavailable for future use immediately and after a
              cooling-off period all secrets will be permanently scrubbed, but
              the record itself will not be removed until related workflow runs
              have been purged.
            </p>
            <p className="py-2">
              Contact your instance administrator for more details.
            </p>
          </div>
          <ModalFooter>
            <LvButton theme="secondary">Ok, understood</LvButton>
          </ModalFooter>
        </ModalPanel>
      </Section>
    </Showcase>
  ),
};

export const ProjectDeletion: Story = {
  name: 'Project deletion',
  render: () => (
    <Showcase>
      <Section
        title="ProjectDeletionModal.render/1"
        description="Requires typing the project name to confirm. The Delete button is disabled until the name matches."
      >
        <ModalPanel
          width="max-w-md"
          title={<ModalTitleWithClose>Delete project</ModalTitleWithClose>}
        >
          <div>
            <p>
              Enter the project name to confirm deletion:{' '}
              <b>Ministry of Health</b>
            </p>
            <p className="my-2">
              Deleting this project will disable access for all users, and
              disable all jobs in the project. The whole project will be deleted
              along with all workflows and work order history, 7 day(s) from
              today.
            </p>
            <LvTextInput id="project_name_confirmation" label="Project name" />
          </div>
          <ModalFooter>
            <LvButton theme="danger" type="submit" disabled>
              Delete project
            </LvButton>
            <LvButton theme="secondary">Cancel</LvButton>
          </ModalFooter>
        </ModalPanel>
      </Section>
    </Showcase>
  ),
};

export const TokenDeletion: Story = {
  name: 'API token deletion',
  render: () => (
    <Showcase>
      <Section
        title="TokenDeletionModal.render/1"
        description="Confirms revoking a personal API access token."
      >
        <ModalPanel
          width="max-w-md"
          title={
            <ModalTitleWithClose>Delete API Access Token</ModalTitleWithClose>
          }
        >
          <div>
            <p className="text-sm text-gray-500">
              Any applications or scripts using this token will no longer be able
              to access the API. You cannot undo this action. <br />
              Are you sure you want to delete this token?
            </p>
          </div>
          <ModalFooter>
            <LvButton theme="danger">Yes</LvButton>
            <LvButton theme="secondary">Cancel</LvButton>
          </ModalFooter>
        </ModalPanel>
      </Section>
    </Showcase>
  ),
};

export const UserDeletion: Story = {
  name: 'User deletion',
  render: () => (
    <Showcase>
      <Section
        title="UserDeletionModal.render/1"
        description="Requires re-typing the user's email to confirm. The note appears when the user still has activity in active projects."
      >
        <ModalPanel
          width="max-w-md"
          title={<ModalTitleWithClose>Delete user</ModalTitleWithClose>}
        >
          <div>
            <p>
              Your account and credential data will be deleted. Please make sure
              none of these credentials are used in production workflows.
            </p>
            <p className="mt-2">
              *Note that you still have activity related to active projects. We
              may not be able to delete them entirely from the app until those
              projects are deleted.
            </p>
            <br />
            <LvTextInput id="scheduled_deletion_email" label="User email" />
          </div>
          <div className="my-[16px] h-0.5 grow bg-gray-100" />
          <div className="flex flex-row-reverse gap-4">
            <LvButton theme="danger" type="submit">
              Delete account
            </LvButton>
            <LvButton theme="secondary">Cancel</LvButton>
          </div>
        </ModalPanel>
      </Section>

      <Section
        title="Blocked (delete_now? + has_activity)"
        description="The variant shown when a user cannot yet be purged because auditable activity remains."
      >
        <ModalPanel
          width="max-w-md"
          title={<ModalTitleWithClose>Delete user</ModalTitleWithClose>}
        >
          <div>
            <p className="text-sm text-gray-500">
              Your account cannot be deleted until their auditable activities
              have also been purged.
              <br />
              <br />
              Audit trails are removed on a project-basis and may be controlled
              by the project owner or a superuser.
            </p>
          </div>
          <ModalFooter>
            <button
              type="button"
              className="inline-flex items-center rounded-md bg-white px-3.5 py-2.5 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-gray-300 ring-inset hover:bg-gray-50"
            >
              Cancel
            </button>
          </ModalFooter>
        </ModalPanel>
      </Section>
    </Showcase>
  ),
};
