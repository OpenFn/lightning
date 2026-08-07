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

import type { StepChange, StructuralChange } from '../utils/workflowDiff';
import { deriveWorkflowChanges } from '../utils/workflowDiff';

/** Blocks with more diff lines than this start collapsed */
const COLLAPSE_LINE_THRESHOLD = 30;

const pluralize = (count: number, noun: string): string =>
  `${count} ${noun}${count === 1 ? '' : 's'}`;

const stepVerb: Record<StepChange['type'], string> = {
  add: 'Add',
  remove: 'Remove',
  update: 'Update',
};

const stepSummary = (step: StepChange): string => {
  switch (step.type) {
    case 'add':
      return pluralize(step.addedLines, 'line');
    case 'remove':
      return pluralize(step.removedLines, 'line');
    case 'update':
      return `Added ${pluralize(step.addedLines, 'line')}, removed ${pluralize(
        step.removedLines,
        'line'
      )}`;
  }
};

/** Collapsible container shared by step blocks and the structure block */
const DiffBlockShell = ({
  title,
  summary,
  defaultExpanded,
  testId,
  children,
}: {
  title: string;
  summary: string;
  defaultExpanded: boolean;
  testId: string;
  children: React.ReactNode;
}) => {
  const [expanded, setExpanded] = useState(defaultExpanded);

  return (
    <div
      className="rounded-lg overflow-hidden border border-gray-200 bg-white"
      data-testid={testId}
    >
      <button
        type="button"
        data-testid="diff-block-toggle"
        onClick={() => setExpanded(prev => !prev)}
        className={cn(
          'w-full px-4 py-2 bg-gray-50 flex items-center justify-between gap-2',
          'hover:bg-gray-100 transition-colors',
          expanded && 'border-b border-gray-200'
        )}
      >
        <span className="flex items-center gap-2 min-w-0">
          <span
            className={cn(
              'transition-transform duration-200',
              expanded && 'rotate-90'
            )}
          >
            <span className="hero-chevron-right h-4 w-4 text-gray-500" />
          </span>
          <span
            className="text-xs text-left font-medium font-mono text-gray-700 truncate"
            data-testid="diff-block-header"
          >
            {title}
          </span>
        </span>
        <span
          className="text-xs text-gray-500 shrink-0"
          data-testid="diff-block-summary"
        >
          {summary}
        </span>
      </button>
      {expanded && children}
    </div>
  );
};

/** One unified-diff row: line-number gutter + marker + code */
const DiffLine = ({
  lineNumber,
  marker,
  content,
}: {
  lineNumber: number;
  marker: '+' | '-' | ' ';
  content: string;
}) => (
  <div
    className={cn(
      'flex min-w-full w-max',
      marker === '+' && 'bg-green-100 text-green-900',
      marker === '-' && 'bg-red-100 text-red-900',
      marker === ' ' && 'text-slate-500'
    )}
    data-testid={
      marker === '+'
        ? 'diff-line-added'
        : marker === '-'
          ? 'diff-line-removed'
          : 'diff-line-context'
    }
  >
    <span className="w-10 shrink-0 pr-2 text-right text-slate-400 select-none">
      {lineNumber}
    </span>
    <span className="whitespace-pre pr-4">
      {marker} {content}
    </span>
  </div>
);

/** Unified diff body for one step: hunks with old/new line numbering */
const DiffHunks = ({ step }: { step: StepChange }) => (
  <div
    className="bg-slate-100 text-slate-800 py-2 overflow-x-auto text-xs font-mono leading-5"
    data-testid="diff-hunks"
  >
    {step.hunks.map((hunk, hunkIndex) => {
      let oldLine = hunk.oldStart;
      let newLine = hunk.newStart;
      return (
        <div key={hunkIndex}>
          {hunkIndex > 0 && (
            <div className="px-4 py-1 text-slate-400 select-none">⋯</div>
          )}
          {hunk.lines.map((line, lineIndex) => {
            const marker = line[0] as '+' | '-' | ' ';
            const content = line.slice(1);
            // Old line numbers for context/removed rows, new for added
            let lineNumber: number;
            if (marker === '+') {
              lineNumber = newLine;
              newLine += 1;
            } else if (marker === '-') {
              lineNumber = oldLine;
              oldLine += 1;
            } else {
              lineNumber = oldLine;
              oldLine += 1;
              newLine += 1;
            }
            return (
              <DiffLine
                key={lineIndex}
                lineNumber={lineNumber}
                marker={marker}
                content={content}
              />
            );
          })}
        </div>
      );
    })}
  </div>
);

const StepDiffBlock = ({ step }: { step: StepChange }) => {
  const totalDiffLines = step.hunks.reduce(
    (total, hunk) => total + hunk.lines.length,
    0
  );
  // Body updates start expanded when small; add/remove blocks (whole-body
  // diffs, usually long and low-signal) always start collapsed.
  const defaultExpanded =
    step.type === 'update' && totalDiffLines <= COLLAPSE_LINE_THRESHOLD;

  return (
    <DiffBlockShell
      title={`${stepVerb[step.type]}(${step.name})`}
      summary={stepSummary(step)}
      defaultExpanded={defaultExpanded}
      testId="diff-block"
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

const StructureBlock = ({ rows }: { rows: StructuralChange[] }) => (
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
 * Renders the change set between the workflow as it was when the user sent
 * their message (`beforeYaml`, null → empty workflow) and the workflow the
 * assistant returned (`afterYaml`). Renders nothing when nothing changed or
 * either YAML fails to parse.
 */
export function WorkflowDiffBlocks({
  beforeYaml,
  afterYaml,
}: {
  beforeYaml: string | null;
  afterYaml: string;
}) {
  // Memoized so YAML parsing/diffing runs once per message, not per render
  const changes = useMemo(
    () => deriveWorkflowChanges(beforeYaml, afterYaml),
    [beforeYaml, afterYaml]
  );

  if (!changes) return null;

  return (
    <div className="space-y-2" data-testid="workflow-diff-blocks">
      {changes.steps.map((step, index) => (
        <StepDiffBlock key={`${step.type}-${step.name}-${index}`} step={step} />
      ))}
      {changes.structure.length > 0 && (
        <StructureBlock rows={changes.structure} />
      )}
    </div>
  );
}
