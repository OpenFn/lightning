/**
 * WorkflowDiffBlocks
 *
 * Claude-Code-style diff blocks rendered under a global assistant reply that
 * changed the workflow: one collapsible block per changed step (unified diff
 * with line numbers and red/green rows) plus a compact "Structure" block for
 * edge/trigger/rename changes.
 *
 * Pure transparency-after-apply — renders nothing when the YAMLs are
 * identical or unparseable, and never touches the apply/preview flow.
 */

import { useMemo, useState } from 'react';

import { useCopyToClipboard } from '#/collaborative-editor/hooks/useCopyToClipboard';
import { cn } from '#/utils/cn';

import type { Token } from '../utils/highlightJs';
import { TOKEN_CLASS, tokenizeJs } from '../utils/highlightJs';
import type {
  AddedRun,
  StepChange,
  StructuralChange,
} from '../utils/workflowDiff';
import { addedRuns, deriveWorkflowChanges } from '../utils/workflowDiff';

import { AdaptorIcon } from './AdaptorIcon';

/** A step to open from its diff block, and the code to highlight in it */
export interface OpenStepTarget {
  jobId?: string;
  name: string;
  added: AddedRun[];
}

const pluralize = (count: number, noun: string): string =>
  `${count} ${noun}${count === 1 ? '' : 's'}`;

// Adds and removes are step lifecycle events rather than code edits, so they
// say so. An update is only ever a body change, which the diff below shows.
const stepVerb: Record<StepChange['type'], string> = {
  add: 'Added step',
  remove: 'Removed step',
  update: 'Updated',
};

/**
 * Line counts in the same shorthand GitHub uses in a file list: a green
 * `+n` and a red `-n`, side by side. A count of zero is dropped rather
 * than shown, so an added step reads `+41` instead of `+41 -0`.
 */
const StepCounts = ({ step }: { step: StepChange }) => (
  <>
    {step.addedLines > 0 && (
      <span className="text-[#1a7f37]">{`+${step.addedLines}`}</span>
    )}
    {step.addedLines > 0 && step.removedLines > 0 && ' '}
    {step.removedLines > 0 && (
      <span className="text-[#cf222e]">{`-${step.removedLines}`}</span>
    )}
    {step.addedLines === 0 && step.removedLines === 0 && (
      <span className="text-[#59636e]">no changes</span>
    )}
  </>
);

/** Collapsible container shared by step blocks and the structure block */
const DiffBlockShell = ({
  title,
  summary,
  defaultExpanded,
  testId,
  action,
  children,
}: {
  title: React.ReactNode;
  summary: React.ReactNode;
  defaultExpanded: boolean;
  testId: string;
  /** Optional control shown beside the counts, outside the collapse toggle */
  action?: React.ReactNode;
  children: React.ReactNode;
}) => {
  const [expanded, setExpanded] = useState(defaultExpanded);

  return (
    <div
      className="rounded-md overflow-hidden border border-[#d1d9e0] bg-white"
      data-testid={testId}
    >
      {/* Header shares the body's surface: a filled header over a white body
          with a rule between reads as three stacked layers. One surface with
          a single hairline reads as one code block. */}
      <div
        className={cn(
          'relative flex items-center gap-2 pl-3 pr-2 py-1.5',
          expanded && 'border-b border-[#d1d9e0]'
        )}
      >
        {/* Stretched behind the header rather than wrapping it, so the title
            can hold a button of its own. No chevron, so the hover state is the
            only cue that the header collapses the block. */}
        <button
          type="button"
          data-testid="diff-block-toggle"
          aria-expanded={expanded}
          aria-label="Toggle diff"
          onClick={() => setExpanded(prev => !prev)}
          className="absolute inset-0 cursor-pointer hover:bg-[#f6f8fa]"
        />
        {/* Flexed so a long step name truncates on its own rather than
            pushing the label it belongs to out of the header. */}
        <span
          className="pointer-events-none relative flex-1 text-xs text-left font-medium text-[#1f2328] min-w-0 flex items-center"
          data-testid="diff-block-header"
        >
          {title}
        </span>
        <span
          className="pointer-events-none relative text-xs shrink-0 font-mono tabular-nums"
          data-testid="diff-block-summary"
        >
          {summary}
        </span>
        {action && (
          <div className="relative flex items-center gap-2">{action}</div>
        )}
      </div>
      {expanded && children}
    </div>
  );
};

/** Syntax-coloured code for one row, from the pre-tokenized body */
const DiffCode = ({
  tokens,
  fallback,
}: {
  tokens?: Token[];
  fallback: string;
}) => {
  if (!tokens) return <>{fallback}</>;
  return (
    <>
      {tokens.map((token, index) => (
        <span key={index} className={TOKEN_CLASS[token.kind]}>
          {token.text}
        </span>
      ))}
    </>
  );
};

/**
 * One unified-diff row. A single gutter, as Claude Code shows it: a removed
 * row carries its old line number and every other row its new one, so the
 * numbers match the step as it now reads in the editor.
 */
const DiffLine = ({
  lineNumber,
  marker,
  content,
  tokens,
}: {
  lineNumber: number;
  marker: '+' | '-' | ' ';
  content: string;
  tokens?: Token[];
}) => (
  <div
    className={cn(
      'flex',
      // Primer's diff line colours. Context rows stay white so the tinted
      // rows are the only thing carrying colour.
      marker === '+' && 'bg-[#e6ffec]',
      marker === '-' && 'bg-[#ffebe9]'
    )}
    data-testid={
      marker === '+'
        ? 'diff-line-added'
        : marker === '-'
          ? 'diff-line-removed'
          : 'diff-line-context'
    }
  >
    {/* Sized to a 4-digit line number and no wider: this panel is narrow and
        every pixel of chrome is a pixel of code lost. The gutter carries a
        deeper tint than its row, as Primer does, so the numbers stay legible
        against the line colour. */}
    <span
      className={cn(
        'w-8 shrink-0 px-1 text-right select-none tabular-nums text-[#59636e]',
        marker === '+' && 'bg-[#ccffd8]',
        marker === '-' && 'bg-[#ffd7d5]'
      )}
      data-testid="diff-gutter"
    >
      {lineNumber}
    </span>
    <span
      className={cn(
        'w-3 shrink-0 select-none text-center',
        marker === '+' && 'text-[#1a7f37]',
        marker === '-' && 'text-[#cf222e]'
      )}
    >
      {marker === ' ' ? '' : marker}
    </span>
    {/* Wraps rather than scrolling: this panel is narrow, and code hidden
        behind a horizontal scrollbar inside a vertically scrolling chat is
        content the reader will never find. */}
    <span className="whitespace-pre-wrap break-words pr-4 min-w-0">
      <DiffCode tokens={tokens} fallback={content} />
    </span>
  </div>
);

/**
 * Unified diff body for one step.
 *
 * Both bodies are tokenized once and rows look up their own line, so a
 * multi-line template literal or block comment is coloured correctly even
 * where the hunk shows only part of it. Ligatures are disabled: in a diff a
 * glyph has to be the character it stands for, or `=>` reads as `⇒` and the
 * reader cannot tell what the code actually says.
 */
const DiffHunks = ({ step }: { step: StepChange }) => {
  const oldTokens = useMemo(() => tokenizeJs(step.oldBody), [step.oldBody]);
  const newTokens = useMemo(() => tokenizeJs(step.newBody), [step.newBody]);

  return (
    <div
      className="bg-white text-[#1f2328] py-1 text-xs font-mono leading-5 [font-variant-ligatures:none]"
      data-testid="diff-hunks"
    >
      {step.hunks.map((hunk, hunkIndex) => {
        let oldLine = hunk.oldStart;
        let newLine = hunk.newStart;
        return (
          <div key={hunkIndex}>
            {hunkIndex > 0 && (
              <div className="bg-[#f6f8fa] px-3 py-1 text-[#59636e] select-none border-y border-[#d1d9e0]">
                ⋯
              </div>
            )}
            {hunk.lines.map((line, lineIndex) => {
              const marker = line[0] as '+' | '-' | ' ';
              const content = line.slice(1);

              // A removed row exists only in the old body, an added row only
              // in the new one; context rows advance both.
              let lineNumber: number;
              let tokens: Token[] | undefined;

              if (marker === '+') {
                lineNumber = newLine;
                tokens = newTokens[newLine - 1];
                newLine += 1;
              } else if (marker === '-') {
                lineNumber = oldLine;
                tokens = oldTokens[oldLine - 1];
                oldLine += 1;
              } else {
                lineNumber = newLine;
                tokens = oldTokens[oldLine - 1];
                oldLine += 1;
                newLine += 1;
              }

              return (
                <DiffLine
                  key={lineIndex}
                  lineNumber={lineNumber}
                  marker={marker}
                  content={content}
                  tokens={tokens}
                />
              );
            })}
          </div>
        );
      })}
    </div>
  );
};

/** Copies a step's body, sized for its feedback label so the header holds still */
const CopyStepButton = ({ body }: { body: string }) => {
  const { copyText, copyToClipboard } = useCopyToClipboard();

  return (
    <button
      type="button"
      data-testid="diff-block-copy"
      onClick={() => void copyToClipboard(body)}
      className="shrink-0 inline-grid text-xs text-[#0969da] hover:underline px-1 py-0.5"
    >
      <span className="col-start-1 row-start-1 invisible" aria-hidden="true">
        Copied!
      </span>
      <span className="col-start-1 row-start-1">{copyText || 'Copy'}</span>
    </button>
  );
};

export const StepDiffBlock = ({
  step,
  onOpenStep,
  canOpenStep,
}: {
  step: StepChange;
  /**
   * Opens this step in the IDE. Takes the name as well as the id: parsing
   * YAML without `id:` fields invents ids, and the apply path parses the
   * same YAML separately, so the two do not agree for a newly added step.
   */
  onOpenStep?: (step: OpenStepTarget) => void;
  /**
   * Whether this step exists on the canvas. A reply whose apply failed, or
   * a step renamed since, resolves to nothing, and a link that silently
   * does nothing is worse than no link.
   */
  canOpenStep?: (step: { jobId?: string; name: string }) => boolean;
}) => {
  const [shaking, setShaking] = useState(false);

  // A removed step has nowhere to go, so it gets no link.
  const canOpen = Boolean(
    onOpenStep &&
      step.type !== 'remove' &&
      (!canOpenStep || canOpenStep({ jobId: step.jobId, name: step.name }))
  );

  const openStep = () =>
    onOpenStep?.({
      jobId: step.jobId,
      name: step.name,
      added: addedRuns(step.hunks),
    });

  // A removed step's new body is empty; the code worth copying is the one
  // that just went away.
  const copyBody = step.type === 'remove' ? step.oldBody : step.newBody;

  return (
    <DiffBlockShell
      title={
        <>
          {/* Non-breaking: a flex item is blockified, so a plain trailing
              space would be trimmed and the label would run into the name.
              The margin is the visual gap on top of it: a mono name set
              against sans needs more than a space's width to separate. */}
          <span className="shrink-0 mr-1">{`${stepVerb[step.type]}\u00a0`}</span>
          {/* A step that can't be opened still answers a click, with the
              same shake a rejected password gets, so the click doesn't
              read as missed. */}
          <button
            type="button"
            data-testid="diff-block-step-pill"
            aria-disabled={!canOpen}
            title={
              canOpen
                ? 'Go to step'
                : step.type === 'remove'
                  ? 'This step was removed'
                  : 'This step is no longer in the workflow'
            }
            onClick={() => (canOpen ? openStep() : setShaking(true))}
            onAnimationEnd={() => setShaking(false)}
            className={cn(
              'pointer-events-auto inline-flex items-center gap-1.5 min-w-0 rounded-md border border-[#d1d9e0] bg-white p-0.5 pr-2',
              canOpen
                ? 'cursor-pointer hover:border-[#afb8c1]'
                : 'cursor-default',
              shaking && 'error-shake'
            )}
          >
            {/* Logos are drawn edge to edge, so an inset tile gives each one
                the same frame whatever its shape. */}
            <span
              className="shrink-0 flex items-center justify-center size-5 rounded bg-[#f6f8fa] overflow-hidden *:size-3.5"
              aria-hidden="true"
            >
              <AdaptorIcon name={step.adaptor} size="sm" />
            </span>
            <span className="font-mono font-normal truncate">{step.name}</span>
          </button>
        </>
      }
      summary={<StepCounts step={step} />}
      defaultExpanded
      testId="diff-block"
      action={
        <>
          <CopyStepButton body={copyBody} />
          {canOpen && (
            <button
              type="button"
              data-testid="diff-block-open-step"
              onClick={openStep}
              className="shrink-0 text-xs text-[#0969da] hover:underline px-1 py-0.5"
            >
              Go to step
            </button>
          )}
        </>
      }
    >
      <DiffHunks step={step} />
    </DiffBlockShell>
  );
};

const structureMarker: Record<
  StructuralChange['change'],
  { symbol: string; className: string }
> = {
  add: { symbol: '+', className: 'text-green-700' },
  remove: { symbol: '-', className: 'text-red-700' },
  modify: { symbol: '~', className: 'text-amber-700' },
};

const structureLabel: Record<StructuralChange['kind'], string> = {
  edge: 'Edge',
  trigger: 'Trigger',
  rename: 'Rename',
};

export const StructureBlock = ({ rows }: { rows: StructuralChange[] }) => (
  <DiffBlockShell
    title="Structure"
    summary={pluralize(rows.length, 'change')}
    defaultExpanded
    testId="structure-block"
  >
    <div className="bg-white text-[#1f2328] py-2 overflow-x-auto text-xs font-mono leading-5 [font-variant-ligatures:none]">
      {rows.map((row, index) => {
        const marker = structureMarker[row.change];
        return (
          <div
            key={index}
            className="flex min-w-full w-max px-4 gap-2"
            data-testid="structure-row"
            data-change={row.change}
          >
            <span className={cn('select-none font-bold', marker.className)}>
              {marker.symbol}
            </span>
            <span className="whitespace-pre">
              <span className="text-slate-500">
                {structureLabel[row.kind]}:
              </span>{' '}
              {row.description}
              {row.detail && (
                <span className="text-slate-500"> ({row.detail})</span>
              )}
            </span>
          </div>
        );
      })}
    </div>
  </DiffBlockShell>
);

/**
 * Presentational tail block: a list of step diffs plus the Structure block.
 * Used both for whole change sets (legacy flat messages) and for the
 * leftovers of an interleaved timeline (steps no status segment claimed).
 */
export const WorkflowChangeBlocks = ({
  steps,
  structure,
  onOpenStep,
  canOpenStep,
}: {
  steps: StepChange[];
  structure: StructuralChange[];
  onOpenStep?: (step: OpenStepTarget) => void;
  canOpenStep?: (step: { jobId?: string; name: string }) => boolean;
}) => {
  if (steps.length === 0 && structure.length === 0) return null;

  return (
    <div className="space-y-2" data-testid="workflow-diff-blocks">
      {steps.map((step, index) => (
        <StepDiffBlock
          key={`${step.type}-${step.name}-${index}`}
          step={step}
          onOpenStep={onOpenStep}
          canOpenStep={canOpenStep}
        />
      ))}
      {structure.length > 0 && <StructureBlock rows={structure} />}
    </div>
  );
};

/**
 * Renders the change set between the workflow as it was when the user sent
 * their message (`beforeYaml`, null → empty workflow) and the workflow the
 * assistant returned (`afterYaml`). Renders nothing when nothing changed or
 * either YAML fails to parse.
 */
export function WorkflowDiffBlocks({
  beforeYaml,
  afterYaml,
  onOpenStep,
  canOpenStep,
}: {
  beforeYaml: string | null;
  afterYaml: string;
  onOpenStep?: (step: OpenStepTarget) => void;
  canOpenStep?: (step: { jobId?: string; name: string }) => boolean;
}) {
  // Memoized so YAML parsing/diffing runs once per message, not per render
  const changes = useMemo(
    () => deriveWorkflowChanges(beforeYaml, afterYaml),
    [beforeYaml, afterYaml]
  );

  if (!changes) return null;

  return (
    <WorkflowChangeBlocks
      steps={changes.steps}
      structure={changes.structure}
      onOpenStep={onOpenStep}
      canOpenStep={canOpenStep}
    />
  );
}
