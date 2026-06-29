import type { Meta, StoryObj } from '@storybook/react-vite';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clones of `LightningWeb.Components.Viewers`
 * (lib/lightning_web/components/viewers.ex): `log_viewer/1`,
 * `dataclip_viewer/1`, `wiped_data_viewer/1` and `collection_preview_viewer/1`.
 *
 * Presentational only. The real `log_viewer` streams lines into a `LogViewer`
 * JS hook and `dataclip_viewer` / `collection_preview_viewer` mount a Monaco
 * `CodeViewer`; here the content is rendered as a static, styled `<pre>` with
 * sample data so the look (dark mono log panel, light JSON code panel) is
 * preserved without Monaco. The `text_ping_loader` waiting state is also
 * reproduced for the log viewer.
 */

// --- text_ping_loader (used by log_viewer's "nothing yet" state) -----------
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

// --- log_viewer -------------------------------------------------------------
type LogLevel = 'INFO' | 'WARN' | 'ERROR' | 'DEBUG';

interface LogLine {
  source: string;
  level: LogLevel;
  message: string;
}

const LOG_LINES: LogLine[] = [
  { source: 'R/T', level: 'INFO', message: 'Starting run for workflow "Patient sync"' },
  { source: 'R/T', level: 'INFO', message: 'Installing @openfn/language-dhis2@6.2.1' },
  { source: 'JOB', level: 'INFO', message: 'Fetching 248 patient records from source' },
  { source: 'JOB', level: 'DEBUG', message: 'GET https://play.dhis2.org/api/trackedEntityInstances' },
  { source: 'JOB', level: 'WARN', message: 'Record 1f3a missing birthDate; defaulting to null' },
  { source: 'JOB', level: 'INFO', message: 'Upserting 248 records to DHIS2' },
  { source: 'JOB', level: 'ERROR', message: 'Conflict: trackedEntityInstance already exists (409)' },
  { source: 'R/T', level: 'INFO', message: 'Run completed with state: failed in 3.142s' },
];

const LOG_LEVEL_COLOR: Record<LogLevel, string> = {
  INFO: 'text-sky-300',
  DEBUG: 'text-gray-400',
  WARN: 'text-yellow-300',
  ERROR: 'text-red-300',
};

function LogViewerPanel({ lines }: { lines: LogLine[] }) {
  return (
    <div className="@container flex grow flex-col rounded-md bg-slate-700 font-mono text-gray-200">
      <div className="border-b border-slate-500">
        <div className="mx-auto px-2">
          <div className="flex h-6 flex-row-reverse items-center @md:h-8">
            <div className="flex cursor-default items-center gap-1 text-xs/4 opacity-75 @md:text-sm/6">
              <span className="hero-adjustments-vertical size-4 @md:size-6" />
              <span>info</span>
              <span className="hero-chevron-down size-4" />
            </div>
          </div>
        </div>
      </div>
      <div className="flex grow">
        <pre className="grow overflow-auto p-3 text-xs leading-relaxed @md:text-sm">
          {lines.map((line, i) => (
            <div key={i} className="flex gap-3 whitespace-pre-wrap">
              <span className="shrink-0 text-gray-500 select-none">
                {String(i + 1).padStart(2, '0')}
              </span>
              <span className="shrink-0 text-gray-400 select-none">
                {line.source}
              </span>
              <span className={cn('shrink-0', LOG_LEVEL_COLOR[line.level])}>
                {line.level.padEnd(5, ' ')}
              </span>
              <span className="text-gray-200">{line.message}</span>
            </div>
          ))}
        </pre>
      </div>
    </div>
  );
}

function LogViewerWaiting({ message }: { message: string }) {
  return (
    <div className="@container flex grow flex-col rounded-md bg-slate-700 font-mono text-gray-200">
      <div className="border-b border-slate-500">
        <div className="mx-auto px-2">
          <div className="flex h-6 flex-row-reverse items-center @md:h-8" />
        </div>
      </div>
      <div className="flex grow">
        <div className="relative grow">
          <div className="relative bg-slate-700 p-12 text-center font-mono text-xs text-gray-200 @md:text-base">
            <TextPingLoader>{message}</TextPingLoader>
          </div>
        </div>
      </div>
    </div>
  );
}

function LogViewerEmpty() {
  return (
    <div className="relative col-span-full m-2 p-12 text-center">
      <span className="relative inline-flex">
        <div className="inline-flex">No logs were received for this run.</div>
      </span>
    </div>
  );
}

// --- dataclip_viewer / collection_preview_viewer (static CodeViewer look) ---
const DATACLIP_JSON = `{
  "data": {
    "patientId": "PT-00482",
    "firstName": "Amara",
    "lastName": "Okafor",
    "birthDate": "1991-04-17",
    "orgUnit": "DiszpKrYNg8",
    "attributes": [
      { "attribute": "w75KJ2mc4zz", "value": "Amara" },
      { "attribute": "zDhUuAYrxNC", "value": "Okafor" }
    ]
  },
  "references": [],
  "cursor": null
}`;

const COLLECTION_JSON = `{
  "key": "patient:PT-00482",
  "value": {
    "status": "synced",
    "lastSeenAt": "2026-06-28T14:02:17Z",
    "attempts": 3
  },
  "createdAt": "2026-06-20T09:11:02Z",
  "updatedAt": "2026-06-28T14:02:17Z"
}`;

function CodeViewerPanel({
  content,
  language,
}: {
  content: string;
  language: string;
}) {
  return (
    <div className="relative h-full rounded-md border border-gray-200 bg-white">
      <button
        type="button"
        className="absolute top-3 right-3 z-10 rounded p-1.5 text-gray-400 transition-colors hover:bg-gray-100/80 hover:text-gray-600 focus:outline-none"
        title="Copy to clipboard"
        aria-label="Copy to clipboard"
      >
        <span className="hero-clipboard h-4 w-4" />
      </button>
      <div className="flex">
        <pre className="grow overflow-auto p-3 pr-12 font-mono text-sm leading-relaxed text-gray-800">
          <code className={`language-${language}`}>{content}</code>
        </pre>
      </div>
    </div>
  );
}

// --- wiped_data_viewer ------------------------------------------------------
function WipedDataViewer({
  dataLabel,
  subject,
  canEditRetention = false,
}: {
  dataLabel: string;
  subject: string;
  canEditRetention?: boolean;
}) {
  return (
    <div className="mb-4 flex flex-col rounded-lg border-2 border-dashed border-gray-200 px-8 pt-6 pb-8">
      <div className="mb-4">
        <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full border-2 border-solid border-gray-300 text-gray-400">
          <span className="hero-code-bracket h-4 w-4" />
        </div>
      </div>
      <div className="mb-4 text-center text-gray-500">
        <h3 className="text-lg font-bold">No {dataLabel} Data here!</h3>
        <p className="text-sm">
          {dataLabel} data for this {subject} has not been retained in
          accordance with your project's data storage policy.
        </p>
      </div>
      <div className="text-center text-sm text-gray-500">
        {canEditRetention ? (
          <>
            You can’t rerun this work order, but you can change{' '}
            <a href="#data-storage" className="link">
              this policy
            </a>{' '}
            for future runs.
          </>
        ) : (
          <>
            Contact one of your{' '}
            <span className="link inline-block" aria-label="admin@example.org">
              project admins
            </span>{' '}
            for more information.
          </>
        )}
      </div>
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Viewers (LiveView Clone)',
  tags: ['useful'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Viewers: Story = {
  render: () => (
    <Showcase className="min-w-[680px]">
      <Section
        title="log_viewer/1"
        description="The dark, monospaced run-log panel with a level filter in its toolbar. Lines are streamed into a JS hook in the app; shown here as static sample output."
      >
        <div className="h-80 max-w-2xl">
          <LogViewerPanel lines={LOG_LINES} />
        </div>
      </Section>

      <Section
        title="log_viewer/1 — waiting"
        description="While a run is enqueued or claimed, the viewer shows a ping loader with a context-specific message."
      >
        <div className="grid max-w-2xl gap-4 sm:grid-cols-2">
          <LogViewerWaiting message="Waiting for worker" />
          <LogViewerWaiting message="Creating runtime & installing adaptors" />
        </div>
      </Section>

      <Section
        title="log_viewer/1 — empty (final state)"
        description="When a run reaches a final state with no logs, an inline empty message is shown instead of the panel."
      >
        <div className="max-w-2xl rounded-md border border-gray-200 bg-white">
          <LogViewerEmpty />
        </div>
      </Section>

      <Section
        title="dataclip_viewer/1"
        description="Renders a dataclip's body as read-only, pretty-printed JSON with a copy button. Backed by Monaco in the app; shown here as a static code panel."
      >
        <div className="h-72 max-w-2xl">
          <CodeViewerPanel content={DATACLIP_JSON} language="json" />
        </div>
      </Section>

      <Section
        title="collection_preview_viewer/1"
        description="Previews a single collection key/value entry as pretty-printed JSON, with long string values truncated. Also Monaco-backed in the app."
      >
        <div className="h-64 max-w-2xl">
          <CodeViewerPanel content={COLLECTION_JSON} language="json" />
        </div>
      </Section>

      <Section
        title="wiped_data_viewer/1"
        description="The dashed empty state shown when input/output data was discarded by the project's data-retention policy. The footer copy depends on whether the viewer can edit the retention policy."
      >
        <div className="grid max-w-3xl gap-4 lg:grid-cols-2">
          <WipedDataViewer dataLabel="Input" subject="step" />
          <WipedDataViewer dataLabel="Output" subject="step" canEditRetention />
        </div>
      </Section>
    </Showcase>
  ),
};
