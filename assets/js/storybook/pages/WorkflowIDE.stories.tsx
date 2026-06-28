import type { Meta, StoryObj } from '@storybook/react-vite';
import { useState } from 'react';

import { cn } from '#/utils/cn';

/**
 * Composite view: the full-screen job IDE
 * (collaborative-editor/components/ide/FullScreenIDE.tsx). Re-creates the IDE
 * layout — the heading bar (job selector, adaptor display, Docs/Metadata
 * toggles, History + Run, close), and the three resizable regions (Input, the
 * code editor, and the run/output viewer).
 *
 * Presentational only: the center editor is a static stand-in for the
 * CollaborativeMonaco editor (no Monaco runtime), and the panels show mock
 * data.
 */
type Token = { t: string; c?: string };

const CODE: Token[][] = [
  [{ t: '// Fetch patients changed since the last run', c: 'text-slate-400' }],
  [
    { t: 'get', c: 'text-sky-700' },
    { t: '(' },
    { t: "'/patients'", c: 'text-emerald-700' },
    { t: ', { query: { since: ' },
    { t: '$.cursor', c: 'text-amber-700' },
    { t: ' } });' },
  ],
  [],
  [
    { t: 'each', c: 'text-sky-700' },
    { t: '(' },
    { t: "'$.data.patients[*]'", c: 'text-emerald-700' },
    { t: ', ' },
    { t: 'state', c: 'text-slate-700' },
    { t: ' => {' },
  ],
  [
    { t: '  return ', c: 'text-purple-700' },
    { t: 'upsert', c: 'text-sky-700' },
    { t: '(' },
    { t: "'trackedEntityInstances'", c: 'text-emerald-700' },
    { t: ', {' },
  ],
  [{ t: '    ...state.data,' }],
  [{ t: '  })(state);' }],
  [{ t: '});' }],
];

const LOG_LINES: { src: string; srcClass: string; msg: string }[] = [
  { src: 'RUN', srcClass: 'text-sky-400', msg: 'Starting run for "Transform data"' },
  { src: 'JOB', srcClass: 'text-emerald-400', msg: 'GET /patients → 200 (37 records)' },
  { src: 'JOB', srcClass: 'text-emerald-400', msg: 'Upserting 37 trackedEntityInstances…' },
  { src: 'RUN', srcClass: 'text-sky-400', msg: 'Run completed in 1.24s' },
];

function HeaderButton({
  active,
  icon,
  children,
}: {
  active?: boolean;
  icon: string;
  children: string;
}) {
  return (
    <button
      type="button"
      className={cn(
        'flex items-center gap-1 rounded px-2 py-1 text-xs transition-colors',
        active
          ? 'bg-primary-100 text-primary-800'
          : 'text-gray-400 hover:bg-gray-100 hover:text-gray-600'
      )}
    >
      <span className={cn(icon, 'h-3.5 w-3.5')} />
      {children}
    </button>
  );
}

function CodeEditor() {
  return (
    <div className="flex h-full flex-col bg-white">
      <div className="flex flex-none items-center gap-2 border-b border-gray-200 bg-slate-50 px-3 py-1.5">
        <span className="hero-document-text h-4 w-4 text-gray-400" />
        <span className="font-mono text-xs text-gray-600">job.js</span>
      </div>
      <div className="flex-1 overflow-auto font-mono text-[13px] leading-6">
        <div className="flex">
          <div className="flex-none select-none py-2 pr-3 pl-3 text-right text-slate-300">
            {CODE.map((_, i) => (
              <div key={i}>{i + 1}</div>
            ))}
          </div>
          <pre className="flex-1 py-2 pr-4 text-slate-800">
            {CODE.map((line, i) => (
              <div key={i} className="min-h-6">
                {line.map((token, j) => (
                  <span key={j} className={token.c}>
                    {token.t}
                  </span>
                ))}
              </div>
            ))}
          </pre>
        </div>
      </div>
    </div>
  );
}

function InputPanel() {
  return (
    <div className="flex h-full flex-col border-r border-gray-200 bg-white">
      <div className="flex-none border-b border-gray-200 px-3 py-2 text-sm font-semibold text-gray-900">
        Input
      </div>
      <div className="flex flex-col gap-3 p-3">
        <div className="flex items-center gap-2">
          <span className="rounded-full bg-green-500 px-2 py-1 font-mono text-xs text-green-900">
            http_request
          </span>
          <span className="font-mono text-xs text-gray-500">
            d4c3b2a1-…
          </span>
        </div>
        <pre className="overflow-auto rounded-md bg-slate-50 p-3 font-mono text-xs text-slate-700 ring-1 ring-gray-200">
          {`{
  "data": {
    "patients": [
      { "id": "p-001", "name": "A. Okafor" },
      { "id": "p-002", "name": "W. Chen" }
    ]
  },
  "cursor": "2026-06-28T09:00:00Z"
}`}
        </pre>
      </div>
    </div>
  );
}

function OutputPanel() {
  const tabs = ['Input', 'Output', 'Log'];
  const [active, setActive] = useState('Log');
  return (
    <div className="flex h-full flex-col border-l border-gray-200 bg-white">
      <div className="flex-none border-b border-gray-200 px-1" role="tablist">
        <div className="flex">
          {tabs.map(tab => (
            <button
              key={tab}
              type="button"
              role="tab"
              aria-selected={tab === active}
              onClick={() => {
                setActive(tab);
              }}
              className={cn(
                'border-b-2 px-3 py-2 text-sm font-medium',
                tab === active
                  ? 'border-primary-500 text-primary-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              )}
            >
              {tab}
            </button>
          ))}
        </div>
      </div>
      <div className="flex-1 overflow-auto bg-slate-800 p-3 font-mono text-xs leading-5">
        {LOG_LINES.map((line, i) => (
          <div key={i} className="flex gap-3">
            <span className={cn('w-8 shrink-0', line.srcClass)}>{line.src}</span>
            <span className="text-slate-200">{line.msg}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

const meta = {
  title: 'Pages/Workflow IDE',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const FullScreen: Story = {
  name: 'Full-screen IDE',
  render: () => (
    <div className="flex h-[700px] flex-col bg-white">
      {/* Heading bar */}
      <div className="flex-none border-b border-gray-200 bg-white">
        <div className="flex items-center justify-between px-4 py-2">
          <div className="flex min-w-0 flex-1 items-center gap-3">
            <button
              type="button"
              className="flex shrink-0 items-center gap-1 rounded-md px-2 py-1 text-sm font-medium text-gray-900 hover:bg-gray-100"
            >
              Transform data
              <span className="hero-chevron-down h-4 w-4 text-gray-400" />
            </button>
            <div className="flex shrink-0 items-center gap-2 rounded-lg border border-slate-200 px-2 py-1">
              <span className="flex h-5 w-5 items-center justify-center rounded bg-primary-100 text-[10px] font-semibold text-primary-700">
                ht
              </span>
              <span className="font-mono text-xs text-gray-700">
                @openfn/language-http
              </span>
              <span className="rounded bg-gray-100 px-1.5 py-0.5 font-mono text-xs text-gray-500">
                latest
              </span>
            </div>
            <div className="flex shrink-0 items-center gap-1">
              <HeaderButton active icon="hero-document-text">
                Docs
              </HeaderButton>
              <HeaderButton icon="hero-sparkles">Metadata</HeaderButton>
            </div>
          </div>
          <div className="flex shrink-0 items-center gap-2">
            <button
              type="button"
              className="inline-flex items-center gap-1.5 rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-primary-500"
            >
              <span className="hero-clock h-4 w-4" />
              History
            </button>
            <button
              type="button"
              className="inline-flex items-center gap-1.5 rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-primary-500"
            >
              <span className="hero-play-solid h-4 w-4" />
              Run
              <span className="hero-chevron-down-mini ml-0.5 h-4 w-4 text-white/80" />
            </button>
            <button
              type="button"
              aria-label="Close IDE"
              className="rounded p-1 transition-colors hover:bg-gray-100"
            >
              <span className="hero-x-mark h-5 w-5 text-gray-500" />
            </button>
          </div>
        </div>
      </div>

      {/* Body: input | editor | output */}
      <div className="flex min-h-0 flex-1">
        <div className="w-80 shrink-0">
          <InputPanel />
        </div>
        <div className="min-w-0 flex-1">
          <CodeEditor />
        </div>
        <div className="w-96 shrink-0">
          <OutputPanel />
        </div>
      </div>
    </div>
  ),
};
