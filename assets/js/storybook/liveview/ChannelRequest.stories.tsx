import type { Meta, StoryObj } from '@storybook/react-vite';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * React clones of `LightningWeb.ChannelRequestLive.Components`
 * (lib/lightning_web/live/channel_request_live/components.ex): `method_badge/1`,
 * `status_code_badge/1`, `status_code_display/1`, `state_pill_with_tooltip/1`
 * (via `channel_state_pill/1`), `section_size_badge/1`, `headers_table/1`,
 * `copy_icon_button/1` and `response_empty/1`.
 *
 * Presentational only — no `phx-*` bindings, clipboard hooks or tooltips. Byte
 * sizes are pre-formatted (the app uses `Helpers.format_bytes/1`).
 */

// --- method_badge -----------------------------------------------------------
type HttpMethod = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE' | 'HEAD';

function methodColor(method: HttpMethod): string {
  switch (method) {
    case 'GET':
      return 'bg-blue-100 text-blue-800';
    case 'POST':
      return 'bg-green-100 text-green-800';
    case 'PUT':
    case 'PATCH':
      return 'bg-amber-100 text-amber-800';
    case 'DELETE':
      return 'bg-red-100 text-red-800';
    default:
      return 'bg-secondary-100 text-secondary-800';
  }
}

function MethodBadge({ method }: { method: HttpMethod }) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded px-2.5 py-0.5 font-mono text-sm font-bold uppercase',
        methodColor(method)
      )}
    >
      {method}
    </span>
  );
}

// --- status_code_badge ------------------------------------------------------
function statusBadgeColor(status: number): string {
  if (status >= 200 && status < 300) return 'bg-green-100 text-green-700';
  if (status >= 300 && status < 400) return 'bg-blue-100 text-blue-700';
  if (status >= 400 && status < 500) return 'bg-amber-100 text-amber-700';
  if (status >= 500) return 'bg-red-100 text-red-700';
  return 'bg-secondary-100 text-secondary-700';
}

function StatusCodeBadge({ status }: { status: number }) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded px-1.5 py-0.5 font-mono text-xs font-bold',
        statusBadgeColor(status)
      )}
    >
      {status}
    </span>
  );
}

// --- status_code_display ----------------------------------------------------
function statusDisplayColor(status: number | null): string {
  if (status === null) return 'text-secondary-400';
  if (status >= 500) return 'text-red-700 bg-red-50';
  if (status >= 400) return 'text-amber-700 bg-amber-50';
  if (status >= 300) return 'text-blue-700 bg-blue-50';
  if (status >= 200) return 'text-green-700 bg-green-50';
  return 'text-secondary-400';
}

function StatusCodeDisplay({ status }: { status: number | null }) {
  return (
    <span
      className={cn(
        'rounded px-1.5 py-0.5 font-mono text-sm font-bold',
        statusDisplayColor(status)
      )}
    >
      {status === null ? '—' : String(status)}
    </span>
  );
}

// --- channel_state_pill (base_pill) -----------------------------------------
type ChannelState = 'pending' | 'success' | 'failed' | 'timeout' | 'error';

const CHANNEL_STATE: Record<ChannelState, { text: string; classes: string }> = {
  pending: { text: 'In Progress', classes: 'bg-blue-200 text-blue-800' },
  success: { text: 'Success', classes: 'bg-green-200 text-green-800' },
  failed: { text: 'Failed', classes: 'bg-red-200 text-red-800' },
  timeout: { text: 'Timeout', classes: 'bg-orange-200 text-orange-800' },
  error: { text: 'Error', classes: 'bg-red-200 text-red-800' },
};

function ChannelStatePill({ state }: { state: ChannelState }) {
  const { text, classes } = CHANNEL_STATE[state];
  return (
    <span
      className={cn(
        'my-auto rounded-full px-4 py-2 text-center align-baseline text-xs leading-none font-medium whitespace-nowrap',
        classes
      )}
    >
      {text}
    </span>
  );
}

function StatePillWithTooltip({
  state,
  tooltip,
}: {
  state: ChannelState;
  tooltip?: string;
}) {
  if (state === 'timeout' && tooltip) {
    return (
      <span className="inline-block cursor-help" title={tooltip}>
        <ChannelStatePill state={state} />
      </span>
    );
  }
  return <ChannelStatePill state={state} />;
}

// --- section_size_badge -----------------------------------------------------
function SectionSizeBadge({ size }: { size: string }) {
  return (
    <span className="font-mono text-xs text-secondary-400">{size}</span>
  );
}

// --- copy_icon_button -------------------------------------------------------
function CopyIconButton({
  title = 'Copy',
  size = 4,
  className,
}: {
  title?: string;
  size?: 3 | 4;
  className?: string;
}) {
  return (
    <button
      type="button"
      className={cn(
        'copy-btn shrink-0 cursor-pointer text-secondary-400 transition-colors hover:text-secondary-600',
        className
      )}
      title={title}
      aria-label={title}
    >
      <span className={cn('hero-clipboard', size === 3 ? 'h-3 w-3' : 'h-4 w-4')} />
    </button>
  );
}

// --- headers_table ----------------------------------------------------------
const REQUEST_HEADERS: [string, string][] = [
  ['accept', 'application/json'],
  ['authorization', '[REDACTED]'],
  ['content-type', 'application/json'],
  ['user-agent', 'OpenFn/2.11.0'],
  ['x-request-id', 'f47ac10b-58cc-4372-a567-0e02b2c3d479'],
];

function HeadersTable({ headers }: { headers: [string, string][] }) {
  return (
    <table className="w-full text-xs">
      <tbody className="divide-y divide-secondary-50">
        {headers.map(([name, value]) => (
          <tr key={name}>
            <td className="w-1/3 py-1.5 pr-3 align-top font-medium whitespace-nowrap text-secondary-500">
              {name}
            </td>
            <td
              className={cn(
                'py-1.5 font-mono break-all',
                value === '[REDACTED]'
                  ? 'text-secondary-400 italic'
                  : 'text-secondary-700'
              )}
            >
              {value}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

// --- response_empty ---------------------------------------------------------
function ResponseEmpty({
  type,
  humanMessage,
  errorCode,
}: {
  type: 'transport' | 'credential';
  humanMessage: string;
  errorCode: string;
}) {
  const { icon, label } =
    type === 'transport'
      ? { icon: 'hero-exclamation-triangle', label: 'No response received' }
      : {
          icon: 'hero-lock-closed',
          label: 'Request not sent — credential error',
        };
  return (
    <div className="border-t border-secondary-100">
      <div className="flex flex-col items-center justify-center px-4 py-8 text-secondary-500">
        <span className={cn(icon, 'mb-3 h-8 w-8 text-secondary-400')} />
        <p className="mb-1 font-medium">{label}</p>
        <p className="mb-2 text-sm">{humanMessage}</p>
        <code className="rounded bg-secondary-100 px-2 py-1 font-mono text-xs">
          {errorCode}
        </code>
      </div>
    </div>
  );
}

// --- shared wrappers --------------------------------------------------------
function Card({ children }: { children: ReactNode }) {
  return (
    <div className="rounded-lg border border-secondary-200 bg-white p-4 shadow-sm">
      {children}
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Channel Request (LiveView Clone)',
  tags: ['useful'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

const METHODS: HttpMethod[] = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD'];

export const ChannelRequest: Story = {
  render: () => (
    <Showcase className="min-w-[680px]">
      <Section
        title="method_badge/1"
        description="A bold, monospaced HTTP-method tag, colour-coded by verb (GET blue, POST green, PUT/PATCH amber, DELETE red, others neutral)."
      >
        <Row>
          {METHODS.map(method => (
            <MethodBadge key={method} method={method} />
          ))}
        </Row>
      </Section>

      <Section
        title="status_code_badge/1"
        description="A compact status-code chip with a filled background, grouped by 2xx/3xx/4xx/5xx."
      >
        <Row>
          {[200, 201, 304, 404, 422, 500, 503].map(status => (
            <StatusCodeBadge key={status} status={status} />
          ))}
        </Row>
      </Section>

      <Section
        title="status_code_display/1"
        description="A larger status-code readout with a tinted background; renders an em dash when no status is available."
      >
        <Row>
          {[200, 301, 404, 500].map(status => (
            <StatusCodeDisplay key={status} status={status} />
          ))}
          <StatusCodeDisplay status={null} />
        </Row>
      </Section>

      <Section
        title="state_pill_with_tooltip/1"
        description="The channel-request state pill. The timeout variant carries a tooltip (hover) with a humanised error explanation."
      >
        <Row>
          <StatePillWithTooltip state="pending" />
          <StatePillWithTooltip state="success" />
          <StatePillWithTooltip state="failed" />
          <StatePillWithTooltip
            state="timeout"
            tooltip="Response timed out — the destination accepted the connection but did not send a response in time"
          />
          <StatePillWithTooltip state="error" />
        </Row>
      </Section>

      <Section
        title="section_size_badge/1"
        description="A muted, monospaced byte-size label shown next to disclosure-section titles."
      >
        <Row>
          <SectionSizeBadge size="512 B" />
          <SectionSizeBadge size="4.2 KB" />
          <SectionSizeBadge size="1.3 MB" />
        </Row>
      </Section>

      <Section
        title="copy_icon_button/1"
        description="A clipboard icon button used to copy headers, bodies and hashes. Available at two sizes."
      >
        <Row>
          <Specimen label="size=4">
            <CopyIconButton title="Copy body" />
          </Specimen>
          <Specimen label="size=3">
            <CopyIconButton title="Copy hash" size={3} />
          </Specimen>
          <Specimen label="on a chip">
            <CopyIconButton
              title="Copy body"
              size={3}
              className="rounded bg-white/80 p-1"
            />
          </Specimen>
        </Row>
      </Section>

      <Section
        title="headers_table/1"
        description="A two-column request/response header table. Redacted values render in muted italics."
      >
        <Card>
          <HeadersTable headers={REQUEST_HEADERS} />
        </Card>
      </Section>

      <Section
        title="response_empty/1"
        description="Shown in the response section when no response was received. The transport variant reports a network failure; the credential variant reports that the request was never sent."
      >
        <div className="grid max-w-3xl gap-4 overflow-hidden rounded-lg border border-secondary-200 bg-white lg:grid-cols-2">
          <ResponseEmpty
            type="transport"
            humanMessage="Connection refused — the destination server is not accepting connections on this port"
            errorCode="econnrefused"
          />
          <ResponseEmpty
            type="credential"
            humanMessage="OAuth token refresh failed — the destination credential could not be renewed"
            errorCode="oauth_refresh_failed"
          />
        </div>
      </Section>
    </Showcase>
  ),
};
