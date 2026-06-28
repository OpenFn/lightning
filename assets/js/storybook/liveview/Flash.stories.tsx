import type { Meta, StoryObj } from '@storybook/react-vite';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clone of `LightningWeb.LiveComponents.Common.flash/1`
 * (lib/lightning_web/live/components/common.ex).
 *
 * The real component is fixed to the bottom-center of the viewport and is
 * dismissed via `phx-click`/`phx-hook="Flash"`. Here it is rendered inline (not
 * fixed) so both kinds are visible together; the dismiss button is decorative.
 */
type FlashKind = 'info' | 'error';

const KIND_STYLES: Record<
  FlashKind,
  { container: string; text: string; icon: string; button: string }
> = {
  error: {
    container: 'bg-red-200 border-red-300',
    text: 'text-red-900',
    icon: 'hero-exclamation-circle-solid',
    button:
      'bg-red-200 text-red-500 hover:bg-red-400 focus:ring-red-800 focus:ring-offset-red-50',
  },
  info: {
    container: 'bg-blue-200 border-blue-300',
    text: 'text-blue-900',
    icon: 'hero-check-circle-solid',
    button:
      'bg-blue-200 text-blue-500 hover:bg-blue-400 focus:ring-blue-800 focus:ring-offset-blue-200',
  },
};

function Flash({ kind, message }: { kind: FlashKind; message: string }) {
  const styles = KIND_STYLES[kind];
  return (
    <div
      data-flash-kind={kind}
      className={cn(
        'flex w-fit justify-center rounded-md p-4',
        styles.container
      )}
    >
      <div
        className={cn(
          'flex items-center justify-between space-x-3',
          styles.text
        )}
      >
        <span className={cn(styles.icon, 'h-5 w-5')} />
        <p className="flex-1 text-sm font-medium" role="alert">
          {message}
        </p>
        <button
          type="button"
          aria-label="Dismiss"
          className={cn(
            'inline-flex rounded-md p-1.5 focus:ring-2 focus:ring-offset-2 focus:outline-none',
            styles.button
          )}
        >
          <span className="hero-x-mark-solid mr-1 ml-1 h-4 w-4 text-white" />
        </button>
      </div>
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Flash (LiveView Clone)',
  parameters: { layout: 'centered' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Flashes: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Flash messages"
        description="Toast-style flashes for the :info and :error kinds. In the app these appear fixed at the bottom-center of the screen."
      >
        <div className="flex flex-col gap-3">
          <Flash kind="info" message="Workflow saved successfully." />
          <Flash
            kind="error"
            message="Could not save workflow. Please try again."
          />
        </div>
      </Section>
    </Showcase>
  ),
};
