import type { Meta, StoryObj } from '@storybook/react-vite';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section, Row } from '../_shared/showcase';

/**
 * React clones of `LightningWeb.RunLive.Components`
 * (lib/lightning_web/live/run_live/components.ex): `detail_list/1`,
 * `list_item/1`, `step_list/1`, `step_item/1`, `step_list_item/1`,
 * `loading_filler/1`, `async_filler/1` and `elapsed_indicator/1`.
 *
 * Presentational only — no `phx-*` bindings, streams or navigation. The
 * `elapsed_indicator` is normally driven by the `ElapsedIndicator` JS hook
 * (which ticks a live duration); here it renders a static, pre-formatted
 * duration. `step_icon` mirrors the server's exit-reason → icon/colour map.
 */

// --- step_icon: reason/error_type → heroicon + colour ----------------------
type StepReason =
  | 'pending'
  | 'success'
  | 'fail'
  | 'crash'
  | 'cancel'
  | 'kill'
  | 'exception'
  | 'lost';

interface StepIconSpec {
  icon: string;
  classes: string;
}

function stepIconSpec(reason: StepReason, errorType?: string): StepIconSpec {
  switch (reason) {
    case 'pending':
      return { icon: 'hero-ellipsis-horizontal-circle-solid', classes: 'text-gray-400' };
    case 'success':
      return { icon: 'hero-check-circle-solid', classes: 'text-green-500' };
    case 'fail':
      return { icon: 'hero-x-circle-solid', classes: 'text-red-500' };
    case 'crash':
      return { icon: 'hero-x-circle-solid', classes: 'text-orange-800' };
    case 'cancel':
      return { icon: 'hero-no-symbol-solid', classes: 'text-grey-600' };
    case 'kill':
      switch (errorType) {
        case 'SecurityError':
        case 'ImportError':
          return { icon: 'hero-shield-exclamation-solid', classes: 'text-yellow-800' };
        case 'TimeoutError':
          return { icon: 'hero-clock-solid', classes: 'text-yellow-800' };
        default:
          return { icon: 'hero-exclamation-circle-solid', classes: 'text-yellow-800' };
      }
    case 'exception':
    case 'lost':
      return { icon: 'hero-exclamation-triangle-solid', classes: 'text-black-800' };
  }
}

function StepIcon({
  reason,
  errorType,
}: {
  reason: StepReason;
  errorType?: string | undefined;
}) {
  const { icon, classes } = stepIconSpec(reason, errorType);
  return (
    <span className={cn('mr-1.5 inline h-5 w-5 flex-shrink-0', icon, classes)} />
  );
}

// --- elapsed_indicator (static) --------------------------------------------
function ElapsedIndicator({ elapsed }: { elapsed: string }) {
  return <div>{elapsed}</div>;
}

// --- detail_list / list_item ------------------------------------------------
function DetailList({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <ul
      className={cn(
        'flex-1 @5xl/viewer:flex-none',
        'divide-y divide-gray-200',
        className
      )}
    >
      {children}
    </ul>
  );
}

function ListItem({
  label,
  labelClassName,
  children,
}: {
  label: ReactNode;
  labelClassName?: string;
  children: ReactNode;
}) {
  return (
    <li className="px-0 py-2 xl:px-3 xl:py-3 2xl:px-4 2xl:py-4">
      <div className="flex items-baseline justify-between text-sm @md/viewer:text-base">
        <dt className={cn('items-center font-medium', labelClassName)}>
          {label}
        </dt>
        <dd className="text-gray-900">{children}</dd>
      </div>
    </li>
  );
}

// --- step_list / step_item --------------------------------------------------
interface StepFixture {
  id: string;
  jobName: string;
  reason: StepReason;
  errorType?: string | undefined;
  elapsed: string;
  exitReason: string;
  startedAt: string;
}

const STEP_FETCH: StepFixture = {
  id: '5d3e1c7a',
  jobName: 'Fetch patients',
  reason: 'success',
  elapsed: '842ms',
  exitReason: 'success',
  startedAt: '14:02:11',
};

const STEP_TRANSFORM: StepFixture = {
  id: 'b81f9a02',
  jobName: 'Transform records',
  reason: 'success',
  elapsed: '1.4s',
  exitReason: 'success',
  startedAt: '14:02:12',
};

const STEP_UPSERT: StepFixture = {
  id: 'a4c7e602',
  jobName: 'Upsert to DHIS2',
  reason: 'fail',
  errorType: 'AdaptorError',
  elapsed: '3.1s',
  exitReason: 'fail',
  startedAt: '14:02:14',
};

function StepItem({
  step,
  selected = false,
  isClone = false,
}: {
  step: StepFixture;
  selected?: boolean;
  isClone?: boolean;
}) {
  return (
    <div
      className={cn(
        'relative flex items-center space-x-3 border-r-4',
        selected
          ? 'border-primary-500 font-semibold'
          : 'border-transparent hover:border-gray-300'
      )}
    >
      <div className="flex items-center">
        <StepIcon reason={step.reason} errorType={step.errorType} />
      </div>
      <div
        className={cn(
          'flex min-w-0 flex-1 items-center space-x-1 pr-1.5',
          isClone && 'opacity-50'
        )}
      >
        {isClone ? (
          <div className="flex">
            <span
              className="cursor-pointer"
              aria-label="This step was originally executed in a previous run. It was skipped in this run; the original output has been used as the starting point for downstream jobs."
            >
              <span className="hero-paper-clip-mini mt-1 mr-1 h-3 w-3 flex-shrink-0 text-gray-500" />
            </span>
          </div>
        ) : null}
        <div className="flex items-center space-x-1 text-sm">
          <span>{step.jobName}</span>
          <button type="button" className="pl-1" aria-label="Inspect Step">
            <span className="hero-document-magnifying-glass-mini h-5 w-5" />
          </button>
        </div>
        <div className="flex-grow text-right text-sm whitespace-nowrap text-gray-500">
          <ElapsedIndicator elapsed={step.elapsed} />
        </div>
      </div>
    </div>
  );
}

function StepList({ children }: { children: ReactNode }) {
  return (
    <ul className="-mb-8">
      {children}
    </ul>
  );
}

// --- step_list_item (history list row) -------------------------------------
function StepListItem({
  step,
  isClone = false,
}: {
  step: StepFixture;
  isClone?: boolean;
}) {
  return (
    <div
      role="row"
      className={cn('group flex w-full items-center', isClone && 'opacity-50')}
    >
      <div
        role="cell"
        className="flex-1 py-2 text-left text-xs font-normal text-gray-500 group-hover:bg-white"
      >
        <div className="flex items-center pl-4">
          <StepIcon reason={step.reason} errorType={step.errorType} />
          <div className="flex items-center gap-2 text-xs text-gray-800">
            <a
              href={`/projects/demo/runs/run-1?step=${step.id}`}
              className="link font-normal text-gray-800 no-underline"
            >
              <span>{step.jobName}</span>
            </a>
            {isClone ? (
              <span
                className="cursor-pointer"
                aria-label="This step was originally executed in a previous run. It was skipped in this run; the original output has been used as the starting point for downstream jobs."
              >
                <span className="hero-paper-clip-mini h-3 w-3 flex-shrink-0 text-gray-500" />
              </span>
            ) : null}
            &bull;
            <span className="text-xs text-gray-500">started {step.startedAt}</span>
          </div>
        </div>
      </div>
      <div
        role="cell"
        className="min-w-[240px] flex-shrink-0 px-4 py-2 text-right group-hover:bg-white"
      >
        <div className="flex items-center justify-end gap-3 text-xs text-gray-500">
          <span
            className="cursor-pointer"
            aria-label="Run this step with the latest version of this workflow"
          >
            <span className="hero-play-circle-mini h-5 w-5 cursor-pointer hover:text-primary-400" />
          </span>
          <span aria-label="Inspect this step" className="cursor-pointer">
            <span className="hero-document-magnifying-glass-mini h-5 w-5" />
          </span>
          <div className="w-16 text-right">
            <ElapsedIndicator elapsed={step.elapsed} />
          </div>
          <span className="w-24 text-right font-mono">
            {step.exitReason}
            {step.errorType ? `:${step.errorType}` : ''}
          </span>
        </div>
      </div>
    </div>
  );
}

// --- loading_filler ---------------------------------------------------------
function LoadingFiller() {
  return (
    <DetailList className="animate-pulse">
      <ListItem
        label={
          <span className="inline-block h-3 w-16 rounded-full bg-slate-500">
            &nbsp;
          </span>
        }
      >
        <span className="inline-block h-3 w-24 rounded-full bg-slate-500" />
      </ListItem>
      <ListItem
        label={
          <span className="inline-block h-3 w-12 rounded-full bg-slate-500">
            &nbsp;
          </span>
        }
      >
        <span className="inline-block h-3 w-12 rounded-full bg-slate-500" />
      </ListItem>
      <ListItem
        label={
          <span className="inline-block h-3 w-12 rounded-full bg-slate-500">
            &nbsp;
          </span>
        }
      >
        <span className="inline-block h-3 w-24 rounded-full bg-slate-500" />
      </ListItem>
    </DetailList>
  );
}

// --- async_filler -----------------------------------------------------------
function AsyncFiller({ message }: { message: string }) {
  return (
    <div data-entity="work_order">
      <div className="py-3 text-center text-gray-500">{message}</div>
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Run Components (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const RunComponents: Story = {
  render: () => (
    <Showcase className="min-w-[680px]">
      <Section
        title="detail_list/1 + list_item/1"
        description="A definition list of run/step metadata. Each item shows a bold label on the left and its value on the right, with rows divided by a hairline."
      >
        <div className="max-w-md rounded-md border border-gray-200 bg-white px-2">
          <DetailList>
            <ListItem label="Work Order">
              <span className="font-mono text-xs text-primary-600">
                a1b2c3d4
              </span>
            </ListItem>
            <ListItem label="Workflow">Patient sync</ListItem>
            <ListItem label="Started">28/06/26 at 2:02pm</ListItem>
            <ListItem label="Finished">28/06/26 at 2:02pm</ListItem>
            <ListItem label="Duration">5.3s</ListItem>
          </DetailList>
        </div>
      </Section>

      <Section
        title="step_list/1 + step_item/1"
        description="The run-inspector step list. Each row pairs a state icon with the job name, an inspect link and the elapsed time. The selected row gets a primary right-border and bold text; clone (skipped) steps are dimmed with a paper-clip marker."
      >
        <div className="max-w-md rounded-md border border-gray-200 bg-white p-2">
          <StepList>
            <li className="group p-2" data-step-id={STEP_FETCH.id}>
              <StepItem step={STEP_FETCH} selected />
            </li>
            <li className="group p-2" data-step-id={STEP_TRANSFORM.id}>
              <StepItem step={STEP_TRANSFORM} />
            </li>
            <li className="group p-2" data-step-id={STEP_UPSERT.id}>
              <StepItem step={STEP_UPSERT} isClone />
            </li>
          </StepList>
        </div>
      </Section>

      <Section
        title="step_list_item/1"
        description="The wider history-page step row (role=row): icon, linked job name, start time, a rerun control, an inspect link, elapsed time and the exit reason."
      >
        <div className="overflow-hidden rounded-md border border-gray-200 bg-gray-100">
          <StepListItem step={STEP_FETCH} />
          <StepListItem step={STEP_TRANSFORM} />
          <StepListItem step={STEP_UPSERT} isClone />
        </div>
      </Section>

      <Section
        title="step_icon/1"
        description="Exit-reason → icon/colour mapping shared by the step rows."
      >
        <Row>
          <StepIcon reason="pending" />
          <StepIcon reason="success" />
          <StepIcon reason="fail" />
          <StepIcon reason="crash" />
          <StepIcon reason="cancel" />
          <StepIcon reason="kill" errorType="SecurityError" />
          <StepIcon reason="kill" errorType="TimeoutError" />
          <StepIcon reason="kill" errorType="OOMError" />
          <StepIcon reason="exception" />
        </Row>
      </Section>

      <Section
        title="loading_filler/1"
        description="A pulsing skeleton shown in place of a detail list while data loads."
      >
        <div className="max-w-md rounded-md border border-gray-200 bg-white px-2">
          <LoadingFiller />
        </div>
      </Section>

      <Section
        title="async_filler/1"
        description="A centered, muted status line used while a work order's runs stream in."
      >
        <div className="max-w-md rounded-md border border-gray-200 bg-white">
          <AsyncFiller message="Loading run history…" />
        </div>
      </Section>

      <Section
        title="elapsed_indicator/1"
        description="Normally a live-ticking duration driven by a JS hook; shown here with static, pre-formatted values."
      >
        <Row>
          <span className="font-mono text-sm text-gray-500">
            <ElapsedIndicator elapsed="842ms" />
          </span>
          <span className="font-mono text-sm text-gray-500">
            <ElapsedIndicator elapsed="1.4s" />
          </span>
          <span className="font-mono text-sm text-gray-500">
            <ElapsedIndicator elapsed="3.1s" />
          </span>
        </Row>
      </Section>
    </Showcase>
  ),
};
