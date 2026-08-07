/**
 * Workflow diff derivation for AI chat transparency.
 *
 * Compares two workflow YAMLs (the doc as it was when the user sent their
 * message vs. the full workflow the global assistant returned) and derives
 * a render-ready change set: per-step unified diffs plus human-readable
 * structural rows (edges, triggers, renames).
 *
 * Pure derivation — no side effects on the workflow or the apply flow.
 */

import { structuredPatch } from 'diff';

import type { StateEdge, StateJob, WorkflowState } from '../../yaml/types';
import { convertWorkflowSpecToState, parseWorkflowYAML } from '../../yaml/util';

export interface DiffHunk {
  /** 1-based line number of the hunk's first line in the old body */
  oldStart: number;
  /** 1-based line number of the hunk's first line in the new body */
  newStart: number;
  /** Unified diff lines, each prefixed with '+', '-' or ' ' */
  lines: string[];
}

export type StepChangeType = 'add' | 'remove' | 'update';

export interface StepChange {
  type: StepChangeType;
  /** Display name (the new name when the step was also renamed) */
  name: string;
  addedLines: number;
  removedLines: number;
  hunks: DiffHunk[];
}

export interface StructuralChange {
  kind: 'edge' | 'trigger' | 'rename';
  change: 'add' | 'remove' | 'modify';
  /** Human row, e.g. "webhook → Transform data" */
  description: string;
  /** Optional dimmed detail, e.g. "condition: always → on_success" */
  detail?: string;
}

export interface WorkflowChangeSet {
  steps: StepChange[];
  structure: StructuralChange[];
}

/** Slice of WorkflowState the diff cares about */
type DiffState = Pick<WorkflowState, 'jobs' | 'triggers' | 'edges'>;

const EMPTY_STATE: DiffState = { jobs: [], triggers: [], edges: [] };

const parseState = (yaml: string): DiffState =>
  convertWorkflowSpecToState(parseWorkflowYAML(yaml));

/** Ensure trailing newline so jsdiff doesn't emit "no newline" markers */
const withTrailingNewline = (body: string): string =>
  body === '' || body.endsWith('\n') ? body : `${body}\n`;

const diffBodies = (
  oldBody: string,
  newBody: string
): { hunks: DiffHunk[]; added: number; removed: number } => {
  const patch = structuredPatch(
    'before',
    'after',
    withTrailingNewline(oldBody),
    withTrailingNewline(newBody),
    undefined,
    undefined,
    { context: 3 }
  );

  let added = 0;
  let removed = 0;
  const hunks: DiffHunk[] = patch.hunks.map(hunk => {
    // Drop jsdiff's "\ No newline at end of file" marker rows
    const lines = hunk.lines.filter(line => !line.startsWith('\\'));
    for (const line of lines) {
      if (line.startsWith('+')) added += 1;
      else if (line.startsWith('-')) removed += 1;
    }
    return { oldStart: hunk.oldStart, newStart: hunk.newStart, lines };
  });

  return { hunks, added, removed };
};

/**
 * Pairs `before` and `after` entities by id first, then matches leftovers
 * with `fallbackKey` (name for jobs, endpoints for edges, type for triggers).
 * The fallback keeps the diff readable when the server did not preserve ids
 * (parsing then invents random UUIDs, which would otherwise turn every
 * unchanged entity into a remove + add pair).
 */
const matchEntities = <T extends { id: string }>(
  before: T[],
  after: T[],
  fallbackKey: (entity: T) => string
): { pairs: Array<[T, T]>; removed: T[]; added: T[] } => {
  const pairs: Array<[T, T]> = [];
  const remainingBefore = [...before];
  const remainingAfter = [...after];

  for (const pick of [(entity: T) => entity.id, fallbackKey] as Array<
    (entity: T) => string
  >) {
    for (let i = remainingBefore.length - 1; i >= 0; i--) {
      const b = remainingBefore[i]!;
      const j = remainingAfter.findIndex(a => pick(a) === pick(b));
      if (j !== -1) {
        pairs.push([b, remainingAfter[j]!]);
        remainingBefore.splice(i, 1);
        remainingAfter.splice(j, 1);
      }
    }
  }

  return { pairs, removed: remainingBefore, added: remainingAfter };
};

/** "webhook → Transform data" using source/target display names */
const edgeEndpoints = (edge: StateEdge, state: DiffState): string => {
  const source = edge.source_trigger_id
    ? (state.triggers.find(t => t.id === edge.source_trigger_id)?.type ??
      'trigger')
    : (state.jobs.find(j => j.id === edge.source_job_id)?.name ??
      'unknown step');
  const target =
    state.jobs.find(j => j.id === edge.target_job_id)?.name ?? 'unknown step';
  return `${source} → ${target}`;
};

const edgeCondition = (edge: StateEdge): string =>
  edge.condition_label ?? edge.condition_type;

const deriveStepChanges = (
  before: DiffState,
  after: DiffState
): { steps: StepChange[]; renames: StructuralChange[] } => {
  const { pairs, removed, added } = matchEntities(
    before.jobs,
    after.jobs,
    job => `name:${job.name}`
  );

  const renames: StructuralChange[] = [];
  const updates = new Map<StateJob, StepChange>();

  for (const [beforeJob, afterJob] of pairs) {
    if (beforeJob.name !== afterJob.name) {
      renames.push({
        kind: 'rename',
        change: 'modify',
        description: `${beforeJob.name} → ${afterJob.name}`,
      });
    }
    if (beforeJob.body !== afterJob.body) {
      const {
        hunks,
        added: addedLines,
        removed: removedLines,
      } = diffBodies(beforeJob.body, afterJob.body);
      updates.set(afterJob, {
        type: 'update',
        name: afterJob.name,
        addedLines,
        removedLines,
        hunks,
      });
    }
  }

  // Emit adds/updates in the after-workflow's order, then removals
  const steps: StepChange[] = [];
  for (const job of after.jobs) {
    const update = updates.get(job);
    if (update) {
      steps.push(update);
    } else if (added.includes(job)) {
      const { hunks, added: addedLines } = diffBodies('', job.body);
      steps.push({
        type: 'add',
        name: job.name,
        addedLines,
        removedLines: 0,
        hunks,
      });
    }
  }
  for (const job of removed) {
    const { hunks, removed: removedLines } = diffBodies(job.body, '');
    steps.push({
      type: 'remove',
      name: job.name,
      addedLines: 0,
      removedLines,
      hunks,
    });
  }

  return { steps, renames };
};

const deriveEdgeChanges = (
  before: DiffState,
  after: DiffState
): StructuralChange[] => {
  const { pairs, removed, added } = matchEntities(
    before.edges,
    after.edges,
    // Endpoint names are only resolvable within each edge's own state, so
    // the fallback key is computed against the matching side.
    edge =>
      `endpoints:${
        before.edges.includes(edge)
          ? edgeEndpoints(edge, before)
          : edgeEndpoints(edge, after)
      }`
  );

  const changes: StructuralChange[] = [];

  for (const edge of added) {
    changes.push({
      kind: 'edge',
      change: 'add',
      description: edgeEndpoints(edge, after),
      detail: `condition: ${edgeCondition(edge)}`,
    });
  }
  for (const edge of removed) {
    changes.push({
      kind: 'edge',
      change: 'remove',
      description: edgeEndpoints(edge, before),
    });
  }

  for (const [beforeEdge, afterEdge] of pairs) {
    const details: string[] = [];
    // Rewiring is detected on ids (display names shift when a step is
    // renamed, which is not an edge change)
    const rewired =
      (beforeEdge.source_trigger_id ?? beforeEdge.source_job_id) !==
        (afterEdge.source_trigger_id ?? afterEdge.source_job_id) ||
      beforeEdge.target_job_id !== afterEdge.target_job_id;
    if (rewired) {
      details.push(`was ${edgeEndpoints(beforeEdge, before)}`);
    }
    const conditionChanged =
      beforeEdge.condition_type !== afterEdge.condition_type ||
      (beforeEdge.condition_expression ?? null) !==
        (afterEdge.condition_expression ?? null) ||
      (beforeEdge.condition_label ?? null) !==
        (afterEdge.condition_label ?? null);
    if (conditionChanged) {
      details.push(
        `condition: ${edgeCondition(beforeEdge)} → ${edgeCondition(afterEdge)}`
      );
    }
    if (beforeEdge.enabled !== afterEdge.enabled) {
      details.push(afterEdge.enabled ? 'enabled' : 'disabled');
    }

    if (details.length > 0) {
      changes.push({
        kind: 'edge',
        change: 'modify',
        description: edgeEndpoints(afterEdge, after),
        detail: details.join('; '),
      });
    }
  }

  return changes;
};

const deriveTriggerChanges = (
  before: DiffState,
  after: DiffState
): StructuralChange[] => {
  const { pairs, removed, added } = matchEntities(
    before.triggers,
    after.triggers,
    trigger => `type:${trigger.type}`
  );

  const changes: StructuralChange[] = [];

  for (const trigger of added) {
    changes.push({
      kind: 'trigger',
      change: 'add',
      description: `${trigger.type} trigger`,
    });
  }
  for (const trigger of removed) {
    changes.push({
      kind: 'trigger',
      change: 'remove',
      description: `${trigger.type} trigger`,
    });
  }

  for (const [beforeTrigger, afterTrigger] of pairs) {
    const details: string[] = [];
    if (beforeTrigger.type !== afterTrigger.type) {
      details.push(`type: ${beforeTrigger.type} → ${afterTrigger.type}`);
    }
    if (beforeTrigger.enabled !== afterTrigger.enabled) {
      details.push(afterTrigger.enabled ? 'enabled' : 'disabled');
    }
    if (
      beforeTrigger.type === 'cron' &&
      afterTrigger.type === 'cron' &&
      beforeTrigger.cron_expression !== afterTrigger.cron_expression
    ) {
      details.push(
        `schedule: ${beforeTrigger.cron_expression} → ${afterTrigger.cron_expression}`
      );
    }

    if (details.length > 0) {
      changes.push({
        kind: 'trigger',
        change: 'modify',
        description: `${afterTrigger.type} trigger`,
        detail: details.join('; '),
      });
    }
  }

  return changes;
};

/**
 * Derives what changed between two workflow YAML snapshots.
 *
 * - `beforeYaml` missing/empty → treated as an empty workflow (all adds).
 * - Any parse failure → `null` (caller renders nothing).
 * - Nothing changed → `null`.
 */
export const deriveWorkflowChanges = (
  beforeYaml: string | null | undefined,
  afterYaml: string
): WorkflowChangeSet | null => {
  let before: DiffState;
  let after: DiffState;
  try {
    after = parseState(afterYaml);
    before = beforeYaml?.trim() ? parseState(beforeYaml) : EMPTY_STATE;
  } catch (error) {
    console.warn(
      '[WorkflowDiff] Could not derive workflow changes from YAML:',
      error
    );
    return null;
  }

  const { steps, renames } = deriveStepChanges(before, after);
  const structure = [
    ...renames,
    ...deriveTriggerChanges(before, after),
    ...deriveEdgeChanges(before, after),
  ];

  if (steps.length === 0 && structure.length === 0) return null;

  return { steps, structure };
};

/**
 * Statuses that announce writing/editing a step, e.g.
 * `Wrote code for "Transform data", "Http"` or `Added step send-to-gmail`.
 * Deliberately excludes read-only statuses ("Read code for...",
 * "Reviewing...", "Checking...") so they never attract a diff block.
 * Bare "add"/"remove" are not matched (a step *named* "Add contact" quoted
 * inside a read status must not read as a write verb) — only inflected
 * forms Apollo actually emits.
 */
const WRITE_STATUS_PATTERN =
  /\b(wrote|writ\w*|edit\w*|updat\w*|add(?:ed|ing|s)|remov(?:ed|ing|es)|creat\w*|renam\w*)\b/i;

export interface StepDiffAssignment {
  /**
   * Timeline segment index → step diffs to render immediately after that
   * status row. Only write/edit statuses that mention a changed step's
   * name attract its block; each block is assigned once (first match wins).
   */
  byStatusIndex: Map<number, StepChange[]>;
  /** Steps no status segment claimed — rendered at the end of the message */
  unmatched: StepChange[];
}

/**
 * Distributes derived step diffs across a message's status segments so each
 * diff renders right after the status that announced writing that step
 * (Claude-Code style). Matching is case-insensitive substring on the step
 * name, which tolerates quotes and punctuation around the name.
 */
export const assignStepDiffsToStatuses = (
  steps: StepChange[],
  segments: Array<{ type: string; content: string }>
): StepDiffAssignment => {
  const byStatusIndex = new Map<number, StepChange[]>();
  const remaining = new Set(steps);

  segments.forEach((segment, index) => {
    if (segment.type !== 'status') return;
    if (remaining.size === 0) return;
    if (!WRITE_STATUS_PATTERN.test(segment.content)) return;

    const content = segment.content.toLowerCase();
    const matched = [...remaining].filter(step =>
      content.includes(step.name.toLowerCase())
    );
    if (matched.length > 0) {
      byStatusIndex.set(index, matched);
      matched.forEach(step => remaining.delete(step));
    }
  });

  return { byStatusIndex, unmatched: steps.filter(s => remaining.has(s)) };
};
