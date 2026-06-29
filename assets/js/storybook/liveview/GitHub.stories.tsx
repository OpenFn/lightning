import type { Meta, StoryObj } from '@storybook/react-vite';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clone of `LightningWeb.Components.GithubComponents.connect_to_github_link/1`
 * (lib/lightning_web/components/github_components.ex).
 *
 * The server component renders a `<.link>` (anchor) styled as a primary button
 * that opens GitHub's OAuth authorize URL in a new tab. The label and tooltip
 * depend on whether the user already has a (now-expired) GitHub token:
 * "Connect" when none, "Reconnect" otherwise.
 *
 * Presentational only: the real authorize URL with encoded query params is
 * replaced with a placeholder, and the Tooltip hook is dropped (the
 * `aria-label` is kept for the expired-token case).
 */

const BASE_CLASS =
  'text-center py-2 px-4 shadow-xs text-sm font-medium rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500 bg-primary-600 hover:bg-primary-700 text-white';

const AUTHORIZE_URL =
  'https://github.com/login/oauth/authorize?client_id=Iv1.example&redirect_uri=https%3A%2F%2Fapp.openfn.org%2Foauth%2Fgithub%2Fcallback';

function ConnectToGithubLink({
  hasExpiredToken = false,
  disabled = false,
}: {
  hasExpiredToken?: boolean;
  disabled?: boolean;
}) {
  return (
    <a
      href={AUTHORIZE_URL}
      target="_blank"
      rel="noreferrer"
      aria-label={hasExpiredToken ? 'Your token has expired' : undefined}
      className={cn(BASE_CLASS, disabled && 'bg-primary-300 cursor-not-allowed')}
    >
      {hasExpiredToken ? 'Reconnect' : 'Connect'} your GitHub Account
    </a>
  );
}

const meta = {
  title: 'LiveView Clones/GitHub (LiveView Clone)',
  tags: ['useful'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const ConnectLink: Story = {
  name: 'connect_to_github_link/1',
  render: () => (
    <Showcase>
      <Section
        title="connect_to_github_link/1"
        description="A primary-button-styled link to GitHub's OAuth authorize page."
      >
        <div className="flex flex-col items-start gap-4">
          <ConnectToGithubLink />
        </div>
      </Section>

      <Section
        title="Reconnect (expired token)"
        description="Shown when the user has a GitHub token that has expired; carries a tooltip via aria-label."
      >
        <div className="flex flex-col items-start gap-4">
          <ConnectToGithubLink hasExpiredToken />
        </div>
      </Section>

      <Section
        title="Disabled"
        description="Adds bg-primary-300 and cursor-not-allowed when disabled."
      >
        <div className="flex flex-col items-start gap-4">
          <ConnectToGithubLink disabled />
        </div>
      </Section>
    </Showcase>
  ),
};
