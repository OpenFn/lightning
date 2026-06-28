import type { Meta, StoryObj } from '@storybook/react-vite';
import type { ReactNode } from 'react';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * React clones of `LightningWeb.Components.Loaders`
 * (lib/lightning_web/components/loaders.ex): `text_ping_loader/1`,
 * `button_loader/1` and `offline_indicator/1`. The offline indicator is
 * normally toggled by `phx-connected`/`phx-disconnected`; it is always shown
 * here for reference.
 */
function TextPingLoader({ children }: { children: ReactNode }) {
  return (
    <span className="relative inline-flex">
      <div className="inline-flex">{children}</div>
      <span className="absolute right-0 -mr-5 flex h-3 w-3">
        <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-primary-400 opacity-75" />
        <span className="relative inline-flex h-3 w-3 rounded-full bg-primary-500" />
      </span>
    </span>
  );
}

function ButtonLoader({ children }: { children: ReactNode }) {
  return (
    <span className="relative inline-flex">
      <button
        type="button"
        className="inline-flex cursor-not-allowed items-center rounded-md bg-white px-4 py-2 text-sm leading-6 font-semibold shadow ring-1 ring-slate-900/10 transition duration-150 ease-in-out"
        disabled
      >
        {children}
      </button>
      <span className="absolute top-0 right-0 -mt-1 -mr-1 flex h-3 w-3">
        <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-primary-400 opacity-75" />
        <span className="relative inline-flex h-3 w-3 rounded-full bg-primary-500" />
      </span>
    </span>
  );
}

function OfflineIndicator() {
  return <span className="hero-signal-slash mr-2 h-6 w-6 text-red-500" />;
}

const meta = {
  title: 'LiveView Clones/Loaders (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Loaders: Story = {
  render: () => (
    <Showcase>
      <Section
        title="text_ping_loader/1"
        description="Inline text with a pinging dot, used while content is loading."
      >
        <Row className="pr-8">
          <TextPingLoader>Loading adaptors</TextPingLoader>
        </Row>
      </Section>

      <Section
        title="button_loader/1"
        description="A disabled button with a pinging badge for in-flight actions."
      >
        <Row>
          <ButtonLoader>Saving…</ButtonLoader>
        </Row>
      </Section>

      <Section
        title="offline_indicator/1"
        description="Shown when the LiveView socket disconnects."
      >
        <Row>
          <Specimen label="hero-signal-slash">
            <OfflineIndicator />
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};
