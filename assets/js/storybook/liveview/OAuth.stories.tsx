import type { Meta, StoryObj } from '@storybook/react-vite';
import { useId } from 'react';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clones of `LightningWeb.Components.Oauth`
 * (lib/lightning_web/live/components/oauth.ex): `scopes_picklist/1`,
 * `missing_client_warning/1` and `oauth_status/1` (with its private
 * sub-components — authorize/reauthorize buttons, the userinfo card, the
 * ping loaders and the alert states).
 *
 * Presentational only: `phx-click`/`phx-target` bindings and the Tooltip hook
 * are dropped. Error copy is transcribed from
 * `LightningWeb.CredentialLive.OAuthErrorFormatter` for realism. The
 * `Common.alert/1` colour classes (lib/lightning_web/live/components/common.ex)
 * are inlined per type so Tailwind keeps them.
 */

// --- Common.alert/1 (header + message + details + single action) -----------
type AlertColor = 'info' | 'success' | 'warning' | 'danger';

const ALERT_COLOR: Record<AlertColor, string> = {
  info: 'blue',
  success: 'green',
  warning: 'yellow',
  danger: 'red',
};

const ALERT_BG: Record<AlertColor, string> = {
  info: 'bg-blue-50',
  success: 'bg-green-50',
  warning: 'bg-yellow-50',
  danger: 'bg-red-50',
};

const ALERT_ICON: Record<AlertColor, string> = {
  info: 'hero-information-circle',
  success: 'hero-check-circle',
  warning: 'hero-exclamation-circle',
  danger: 'hero-x-circle',
};

const ALERT_ICON_TEXT: Record<AlertColor, string> = {
  info: 'text-blue-400',
  success: 'text-green-400',
  warning: 'text-yellow-400',
  danger: 'text-red-400',
};

const ALERT_HEADER_TEXT: Record<AlertColor, string> = {
  info: 'text-blue-800',
  success: 'text-green-800',
  warning: 'text-yellow-800',
  danger: 'text-red-800',
};

const ALERT_BODY_TEXT: Record<AlertColor, string> = {
  info: 'text-blue-700',
  success: 'text-green-700',
  warning: 'text-yellow-700',
  danger: 'text-red-700',
};

const ALERT_ACTION: Record<AlertColor, string> = {
  info: 'bg-blue-50 text-blue-800 hover:bg-blue-100 focus:ring-blue-600 focus:ring-offset-blue-50',
  success:
    'bg-green-50 text-green-800 hover:bg-green-100 focus:ring-green-600 focus:ring-offset-green-50',
  warning:
    'bg-yellow-50 text-yellow-800 hover:bg-yellow-100 focus:ring-yellow-600 focus:ring-offset-yellow-50',
  danger:
    'bg-red-50 text-red-800 hover:bg-red-100 focus:ring-red-600 focus:ring-offset-red-50',
};

function Alert({
  type,
  header,
  className,
  actionText,
  children,
}: {
  type: AlertColor;
  header?: string;
  className?: string;
  actionText?: string;
  children: ReactNode;
}) {
  const color = ALERT_COLOR[type];
  return (
    <div className={cn('rounded-md p-4 text-wrap', ALERT_BG[type], className)}>
      <div className={cn('flex', header ? 'items-start' : 'items-center')}>
        <div className="shrink-0">
          <span
            className={cn(ALERT_ICON[type], 'block h-5 w-5', ALERT_ICON_TEXT[type])}
          />
        </div>
        <div className="ml-3 min-w-0 flex-1">
          {header ? (
            <>
              <h3 className={cn('text-sm font-medium', ALERT_HEADER_TEXT[type])}>
                {header}
              </h3>
              <div className={cn('mt-2 text-sm', ALERT_BODY_TEXT[type])}>
                {children}
              </div>
            </>
          ) : (
            <div className={cn('text-sm', ALERT_BODY_TEXT[type])}>
              {children}
            </div>
          )}
          {actionText ? (
            <div className="mt-4">
              <div className="-mx-2 -my-1.5 flex">
                <button
                  type="button"
                  className={cn(
                    'rounded-md px-2 py-1.5 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-offset-2',
                    ALERT_ACTION[color as AlertColor]
                  )}
                >
                  {actionText}
                </button>
              </div>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

// --- input type="checkbox" (used by scopes_picklist) -----------------------
function CheckboxInput({
  name,
  value,
  label,
  defaultChecked,
  disabled,
}: {
  name: string;
  value: string;
  label: string;
  defaultChecked?: boolean;
  disabled?: boolean;
}) {
  const id = useId();
  return (
    <div>
      <label
        htmlFor={id}
        className="flex items-center gap-2 text-sm leading-6 text-slate-600"
      >
        <input
          id={id}
          type="checkbox"
          name={name}
          value={value}
          defaultChecked={defaultChecked}
          disabled={disabled}
          className="rounded border-gray-300 text-primary-600 focus:ring-primary-600 checked:disabled:bg-primary-300 checked:disabled:border-primary-300 checked:bg-primary-600 checked:border-primary-600 focus:outline-none transition duration-200 cursor-pointer"
        />
        {label}
      </label>
    </div>
  );
}

// --- scopes_picklist/1 ------------------------------------------------------
function ScopesPicklist({
  id,
  provider,
  docUrl,
  scopes,
  selectedScopes,
  mandatoryScopes,
  disabled,
}: {
  id: string;
  provider: string;
  docUrl?: string;
  scopes: string[];
  selectedScopes: string[];
  mandatoryScopes: string[];
  disabled?: boolean;
}) {
  return (
    <div id={id} className="mt-5">
      <h3 className="leading-6 text-slate-800 pb-2 mb-2">
        <div className="flex flex-row text-sm font-semibold">
          Select permissions
          <span
            className="relative ml-1 cursor-pointer"
            aria-label="Select permissions associated to your OAuth2 Token"
          >
            <span className="hero-information-circle-solid w-4 h-4 text-primary-600 opacity-50" />
          </span>
        </div>
        {docUrl ? (
          <div className="flex flex-row text-xs mt-1">
            Learn more about {provider} permissions
            <a
              target="_blank"
              rel="noreferrer"
              href={docUrl}
              className="whitespace-nowrap font-medium text-blue-700 hover:text-blue-600"
            >
              &nbsp;here
            </a>
          </div>
        ) : null}
      </h3>
      <div className="flex flex-wrap gap-1">
        {scopes.map(scope => (
          <CheckboxInput
            key={scope}
            name={scope}
            value={scope}
            label={scope}
            defaultChecked={
              selectedScopes.includes(scope) || mandatoryScopes.includes(scope)
            }
            disabled={mandatoryScopes.includes(scope) || Boolean(disabled)}
          />
        ))}
      </div>
    </div>
  );
}

// --- missing_client_warning/1 ----------------------------------------------
function MissingClientWarning() {
  return (
    <Alert type="danger" header="OAuth client not found">
      <p>
        The associated Oauth client for this credential cannot be found. Create
        a new client or contact your administrator.
      </p>
    </Alert>
  );
}

// --- oauth_status/1 sub-components ------------------------------------------
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

function AuthorizeButton({ provider }: { provider: string }) {
  return (
    <button
      type="button"
      className="rounded-md text-sm font-semibold shadow-xs cursor-pointer disabled:cursor-auto px-3 py-2 bg-primary-600 hover:bg-primary-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600"
    >
      <span className="text-normal">Sign in with {provider}</span>
    </button>
  );
}

function ReauthorizeButton({ provider }: { provider: string }) {
  return (
    <div className="text-sm text-gray-600">
      If your credential isn't working as expected, you can{' '}
      <button
        type="button"
        className="font-medium text-blue-600 hover:text-blue-500"
      >
        reauthenticate with {provider}
      </button>
    </div>
  );
}

function UserinfoCard({
  provider,
  name,
  email,
  picture,
}: {
  provider: string;
  name: string;
  email: string;
  picture: string;
}) {
  return (
    <div className="bg-green-50 border border-green-200 rounded-lg p-4">
      <div className="flex items-center">
        <img src={picture} alt={name} className="h-16 w-16 rounded-full" />
        <div className="ml-4">
          <h3 className="text-base font-semibold text-gray-900">{name}</h3>
          <p className="text-sm text-gray-600">{email}</p>
          <p className="text-xs text-green-600 mt-1">
            Successfully authenticated with {provider}
          </p>
        </div>
      </div>
    </div>
  );
}

// --- oauth_status/1 ---------------------------------------------------------
type OauthState =
  | 'idle'
  | 'authenticating'
  | 'fetching_userinfo'
  | 'complete'
  | 'error'
  | 'scopes_changed';

const SAMPLE_USERINFO = {
  name: 'Jane Mwangi',
  email: 'jane.mwangi@example.org',
  picture: 'https://i.pravatar.cc/128?img=47',
};

function OauthStatus({
  state,
  provider,
}: {
  state: OauthState;
  provider: string;
}) {
  return (
    <div className="space-y-4">
      {state === 'scopes_changed' ? (
        <Alert
          type="warning"
          header="Reauthentication Required"
          actionText="Reauthenticate"
        >
          <p>You've changed the permissions for this credential.</p>
          <p className="mt-2 text-sm whitespace-pre-line">
            Please reauthenticate with {provider} to apply these changes.
          </p>
        </Alert>
      ) : null}

      {state === 'idle' ? <AuthorizeButton provider={provider} /> : null}

      {state === 'authenticating' ? (
        <TextPingLoader>Authenticating with {provider}...</TextPingLoader>
      ) : null}

      {state === 'fetching_userinfo' ? (
        <TextPingLoader>
          Fetching user information from {provider}...
        </TextPingLoader>
      ) : null}

      {state === 'complete' ? (
        <>
          <UserinfoCard
            provider={provider}
            name={SAMPLE_USERINFO.name}
            email={SAMPLE_USERINFO.email}
            picture={SAMPLE_USERINFO.picture}
          />
          <ReauthorizeButton provider={provider} />
        </>
      ) : null}

      {state === 'error' ? (
        <Alert type="danger" header="Invalid Access Token" actionText="Reauthorize">
          <p>The access token received from {provider} is invalid.</p>
          <p className="mt-2 text-sm whitespace-pre-line">
            This might indicate an issue with the authorization process.
          </p>
        </Alert>
      ) : null}
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/OAuth (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const ScopesPicklistStory: Story = {
  name: 'scopes_picklist/1',
  render: () => (
    <Showcase className="max-w-lg">
      <Section
        title="scopes_picklist/1"
        description="Checkbox grid of OAuth scopes. Mandatory scopes are checked and disabled."
      >
        <ScopesPicklist
          id="google-scopes"
          provider="Google"
          docUrl="https://developers.google.com/identity/protocols/oauth2/scopes"
          scopes={[
            'userinfo.email',
            'userinfo.profile',
            'spreadsheets',
            'drive.readonly',
            'calendar',
          ]}
          selectedScopes={['userinfo.email', 'spreadsheets']}
          mandatoryScopes={['userinfo.email']}
        />
      </Section>

      <Section
        title="scopes_picklist/1 — disabled"
        description="All checkboxes disabled, e.g. while a request is in flight."
      >
        <ScopesPicklist
          id="github-scopes"
          provider="GitHub"
          scopes={['repo', 'workflow', 'read:org']}
          selectedScopes={['repo']}
          mandatoryScopes={['repo']}
          disabled
        />
      </Section>
    </Showcase>
  ),
};

export const MissingClientWarningStory: Story = {
  name: 'missing_client_warning/1',
  render: () => (
    <Showcase className="max-w-lg">
      <Section
        title="missing_client_warning/1"
        description="Danger alert shown when a credential's OAuth client cannot be found."
      >
        <MissingClientWarning />
      </Section>
    </Showcase>
  ),
};

export const OauthStatusStory: Story = {
  name: 'oauth_status/1',
  render: () => (
    <Showcase className="max-w-lg">
      <Section
        title="oauth_status/1 — :idle"
        description="Initial state with the authorize button."
      >
        <OauthStatus state="idle" provider="Google" />
      </Section>

      <Section
        title="oauth_status/1 — :authenticating & :fetching_userinfo"
        description="In-flight loading states with a pinging dot."
      >
        <div className="flex flex-col gap-6 pr-8">
          <OauthStatus state="authenticating" provider="Google" />
          <OauthStatus state="fetching_userinfo" provider="Google" />
        </div>
      </Section>

      <Section
        title="oauth_status/1 — :complete"
        description="Success state showing the fetched user info card and a reauthenticate link."
      >
        <OauthStatus state="complete" provider="Google" />
      </Section>

      <Section
        title="oauth_status/1 — :error"
        description="An error alert with copy from OAuthErrorFormatter and a retry action."
      >
        <OauthStatus state="error" provider="GitHub" />
      </Section>

      <Section
        title="oauth_status/1 — scopes_changed"
        description="Warning shown when selected scopes differ from the last authorization."
      >
        <OauthStatus state="scopes_changed" provider="Google" />
      </Section>
    </Showcase>
  ),
};
