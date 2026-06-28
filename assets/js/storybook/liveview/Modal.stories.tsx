import type { Meta, StoryObj } from '@storybook/react-vite';
import { useState } from 'react';
import type { ReactNode } from 'react';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clone of `LightningWeb.Components.Modal.modal/1`
 * (lib/lightning_web/live/components/modal.ex).
 *
 * Mirrors the dialog panel markup (title, subtitle, divider, body, footer) and
 * the shared `modal-backdrop` utility. The real component manages show/hide
 * with `JS` transitions and focus trapping; here open/close is local state.
 */
function FooterButton({
  variant,
  children,
  onClick,
}: {
  variant: 'primary' | 'secondary';
  children: ReactNode;
  onClick?: () => void;
}) {
  const classes =
    variant === 'primary'
      ? 'bg-primary-600 hover:bg-primary-500 text-white'
      : 'bg-white hover:bg-gray-50 text-gray-900 ring-1 ring-gray-300 ring-inset';
  return (
    <button
      type="button"
      onClick={onClick}
      className={`cursor-pointer rounded-md px-3 py-2 text-sm font-semibold shadow-xs ${classes}`}
    >
      {children}
    </button>
  );
}

function ModalPanel({
  title,
  subtitle,
  children,
  footer,
}: {
  title: string;
  subtitle?: string;
  children: ReactNode;
  footer: ReactNode;
}) {
  return (
    <div className="max-w-3xl rounded-xl bg-white py-[24px] shadow-lg shadow-zinc-700/10 ring-1 ring-zinc-700/10">
      <header className="pr-[24px] pl-[24px]">
        <h1 className="text-lg leading-5 font-semibold text-zinc-800">
          {title}
        </h1>
        {subtitle ? (
          <p className="mt-2 text-sm leading-4.5 text-zinc-600">{subtitle}</p>
        ) : null}
      </header>
      <div className="my-[16px] h-0.5 grow bg-gray-100" />
      <section className="pr-[24px] pl-[24px] text-sm text-gray-700">
        {children}
      </section>
      <div className="mt-[16px]" />
      <footer className="gap-3 px-[24px] sm:flex sm:flex-row-reverse">
        {footer}
      </footer>
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Modal (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Anatomy: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Dialog panel"
        description="The modal panel as it appears when open — title, subtitle, divider, body and a reversed footer button row."
      >
        <div className="flex justify-center rounded-lg bg-gray-100 p-10">
          <ModalPanel
            title="Delete workflow?"
            subtitle="This action cannot be undone."
            footer={
              <>
                <FooterButton variant="primary">Delete</FooterButton>
                <FooterButton variant="secondary">Cancel</FooterButton>
              </>
            }
          >
            <p>
              Deleting this workflow removes all of its jobs, triggers and run
              history. Are you sure you want to continue?
            </p>
          </ModalPanel>
        </div>
      </Section>
    </Showcase>
  ),
};

export const Interactive: Story = {
  render: function InteractiveModal() {
    const [open, setOpen] = useState(false);
    return (
      <div className="flex min-h-[420px] items-center justify-center">
        <FooterButton
          variant="primary"
          onClick={() => {
            setOpen(true);
          }}
        >
          Open modal
        </FooterButton>
        {open ? (
          <div className="fixed inset-0 z-50">
            <button
              type="button"
              aria-label="Close"
              className="modal-backdrop"
              onClick={() => {
                setOpen(false);
              }}
            />
            <div className="fixed inset-0 flex items-center justify-center p-4">
              <ModalPanel
                title="GitHub sync"
                subtitle="Connect this project to a repository."
                footer={
                  <>
                    <FooterButton
                      variant="primary"
                      onClick={() => {
                        setOpen(false);
                      }}
                    >
                      Connect
                    </FooterButton>
                    <FooterButton
                      variant="secondary"
                      onClick={() => {
                        setOpen(false);
                      }}
                    >
                      Cancel
                    </FooterButton>
                  </>
                }
              >
                <p>Choose a repository and branch to sync your workflows.</p>
              </ModalPanel>
            </div>
          </div>
        ) : null}
      </div>
    );
  },
};
