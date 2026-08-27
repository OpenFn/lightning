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

import { cn } from '#/utils/cn';

import type { Token } from '../utils/highlightJs';
import { TOKEN_CLASS, tokenizeJs } from '../utils/highlightJs';
import type { StepChange, StructuralChange } from '../utils/workflowDiff';
import { deriveWorkflowChanges } from '../utils/workflowDiff';

const pluralize = (count: number, noun: string): string =>
  `${count} ${noun}${count === 1 ? '' : 's'}`;

const stepVerb: Record<StepChange['type'], string> = {
  add: 'Add',
  remove: 'Remove',
  update: 'Update',
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
  title: string;
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
          'flex items-center gap-2 pr-2',
          expanded && 'border-b border-[#d1d9e0]'
        )}
      >
        <button
          type="button"
          data-testid="diff-block-toggle"
          onClick={() => setExpanded(prev => !prev)}
          className={cn(
            'flex-1 min-w-0 px-3 py-1.5 flex items-center justify-between gap-2',
            // No chevron, so the hover state is the only cue that the header
            // collapses the block.
            'cursor-pointer hover:bg-[#f6f8fa]'
          )}
        >
          <span
            className="text-xs text-left font-medium font-mono text-[#1f2328] truncate"
            data-testid="diff-block-header"
          >
            {title}
          </span>
          <span
            className="text-xs shrink-0 font-mono tabular-nums"
            data-testid="diff-block-summary"
          >
            {summary}
          </span>
        </button>
        {action}
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
 * One unified-diff row.
 *
 * Two gutters, old and new, each blank where that side has no line: a
 * removed row exists only in the old file and an added row only in the new
 * one. Collapsing them into a single column makes a diff read as though the
 * same line number appears twice with different content.
 */
const DiffLine = ({
  oldLineNumber,
  newLineNumber,
  marker,
  content,
  tokens,
}: {
  oldLineNumber: number | null;
  newLineNumber: number | null;
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
    {/* Both gutters sized to a 4-digit line number and no wider: this panel
        is narrow and every pixel of chrome is a pixel of code lost. */}
    {/* Both gutters sized to a 4-digit line number and no wider: this panel
        is narrow and every pixel of chrome is a pixel of code lost. The
        gutter carries a deeper tint than its row, as Primer does, so the
        numbers stay legible against the line colour. */}
    <span
      className={cn(
        'w-7 shrink-0 pl-1 text-right select-none tabular-nums text-[#59636e]',
        marker === '+' && 'bg-[#ccffd8]',
        marker === '-' && 'bg-[#ffd7d5]'
      )}
      data-testid="diff-gutter-old"
    >
      {oldLineNumber ?? ''}
    </span>
    <span
      className={cn(
        'w-7 shrink-0 pr-1 text-right select-none tabular-nums text-[#59636e]',
        marker === '+' && 'bg-[#ccffd8]',
        marker === '-' && 'bg-[#ffd7d5]'
      )}
      data-testid="diff-gutter-new"
    >
      {newLineNumber ?? ''}
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
              let oldLineNumber: number | null = null;
              let newLineNumber: number | null = null;
              let tokens: Token[] | undefined;

              if (marker === '+') {
                newLineNumber = newLine;
                tokens = newTokens[newLine - 1];
                newLine += 1;
              } else if (marker === '-') {
                oldLineNumber = oldLine;
                tokens = oldTokens[oldLine - 1];
                oldLine += 1;
              } else {
                oldLineNumber = oldLine;
                newLineNumber = newLine;
                tokens = oldTokens[oldLine - 1];
                oldLine += 1;
                newLine += 1;
              }

              return (
                <DiffLine
                  key={lineIndex}
                  oldLineNumber={oldLineNumber}
                  newLineNumber={newLineNumber}
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

export const StepDiffBlock = ({
  step,
  onOpenStep,
}: {
  step: StepChange;
  /**
   * Opens this step in the IDE. Takes the name as well as the id: parsing
   * YAML without `id:` fields invents ids, and the apply path parses the
   * same YAML separately, so the two do not agree for a newly added step.
   */
  onOpenStep?: (step: { jobId?: string; name: string }) => void;
}) => {
  // A removed step has nowhere to go, so it gets no link.
  const canOpen = Boolean(onOpenStep && step.type !== 'remove');

  return (
    <DiffBlockShell
      title={`${stepVerb[step.type]}(${step.name})`}
      summary={<StepCounts step={step} />}
      defaultExpanded
      testId="diff-block"
      action={
        canOpen ? (
          <button
            type="button"
            data-testid="diff-block-open-step"
            onClick={() => {
              onOpenStep?.({ jobId: step.jobId, name: step.name });
            }}
            className="shrink-0 text-xs text-[#0969da] hover:underline px-1 py-0.5"
          >
            Open
          </button>
        ) : undefined
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
    <div className="bg-slate-100 text-slate-800 py-2 overflow-x-auto text-xs font-mono leading-5">
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
}: {
  steps: StepChange[];
  structure: StructuralChange[];
  onOpenStep?: (step: { jobId?: string; name: string }) => void;
}) => {
  if (steps.length === 0 && structure.length === 0) return null;

  return (
    <div className="space-y-2" data-testid="workflow-diff-blocks">
      {steps.map((step, index) => (
        <StepDiffBlock
          key={`${step.type}-${step.name}-${index}`}
          step={step}
          onOpenStep={onOpenStep}
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
}: {
  beforeYaml: string | null;
  afterYaml: string;
  onOpenStep?: (step: { jobId?: string; name: string }) => void;
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
    />
  );
}
