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
import type { WorkflowSnapshot } from '../types/ai-assistant';

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
  /**
   * Whole bodies either side of the change. Syntax highlighting tokenizes
   * these rather than the hunk rows, so a template literal or block comment
   * spanning several lines is coloured correctly even where the hunk shows
   * only part of it.
   */
  oldBody: string;
  newBody: string;
  /**
   * Id of the step in the workflow the reply produced, so the block can link
   * to it. Absent for a removed step: it is not there to open.
   */
  jobId?: string;
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
      // Apollo re-serializes the whole document on every mutation, which
      // turns a `body: |` block scalar into an inline scalar and back. The
      // parsed strings then differ by a trailing newline while the diff
      // itself is empty. Emitting that would hang a blank block under a
      // status row on almost every reply.
      if (addedLines > 0 || removedLines > 0) {
        updates.set(afterJob, {
          type: 'update',
          name: afterJob.name,
          addedLines,
          removedLines,
          hunks,
          oldBody: beforeJob.body,
          newBody: afterJob.body,
          jobId: afterJob.id,
        });
      }
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
        oldBody: '',
        newBody: job.body,
        jobId: job.id,
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
      oldBody: job.body,
      newBody: '',
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
    // Rewiring is detected on ids, because display names shift when a step
    // is renamed and that is not an edge change. Ids alone are not enough
    // though: parsing YAML without `id:` fields invents a fresh UUID per
    // entity, so two parses of the same workflow never agree on ids and
    // every edge would report itself rewired. Require the endpoints to have
    // actually moved as well.
    const idsDiffer =
      (beforeEdge.source_trigger_id ?? beforeEdge.source_job_id) !==
        (afterEdge.source_trigger_id ?? afterEdge.source_job_id) ||
      beforeEdge.target_job_id !== afterEdge.target_job_id;
    const rewired =
      idsDiffer &&
      edgeEndpoints(beforeEdge, before) !== edgeEndpoints(afterEdge, after);
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
const diffStates = (
  before: DiffState,
  after: DiffState
): WorkflowChangeSet | null => {
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
 * Parsed states, keyed by the YAML that produced them.
 *
 * `deriveSnapshotChanges` re-runs whenever a new snapshot arrives and starts
 * again from the baseline, so K snapshots would otherwise parse K(K+1)/2
 * times. Each parse compiles a fresh Ajv validator, which is far too much
 * work to repeat on the main thread mid-reply. Bounded so a long session
 * cannot grow it without limit; snapshots are re-read in order, so evicting
 * the oldest keeps the entries that are about to be used again.
 */
const MAX_CACHED_STATES = 64;
const parsedStates = new Map<string, DiffState | null>();

const rememberState = (yaml: string, state: DiffState | null) => {
  if (parsedStates.size >= MAX_CACHED_STATES) {
    const oldest = parsedStates.keys().next().value;
    if (oldest !== undefined) parsedStates.delete(oldest);
  }
  parsedStates.set(yaml, state);
};

/** Parsed state, or null when the YAML could not be read */
const tryParseState = (yaml: string): DiffState | null => {
  if (parsedStates.has(yaml)) {
    const cached = parsedStates.get(yaml) ?? null;
    // Re-insert so eviction is least-recently-used. Plain insertion order
    // evicts the front of the chain, which is exactly what the next pass
    // reads first, so a chain longer than the cap would thrash.
    parsedStates.delete(yaml);
    parsedStates.set(yaml, cached);
    return cached;
  }

  try {
    const state = parseState(yaml);
    rememberState(yaml, state);
    return state;
  } catch (error) {
    console.warn(
      '[WorkflowDiff] Could not derive workflow changes from YAML:',
      error
    );
    rememberState(yaml, null);
    return null;
  }
};

export const deriveWorkflowChanges = (
  beforeYaml: string | null | undefined,
  afterYaml: string
): WorkflowChangeSet | null => {
  const after = tryParseState(afterYaml);
  if (!after) return null;

  const before = beforeYaml?.trim() ? tryParseState(beforeYaml) : EMPTY_STATE;
  if (!before) return null;

  return diffStates(before, after);
};

export interface StepDiffAssignment {
  /**
   * Timeline segment index → step diffs to render immediately after that
   * status row.
   */
  byStatusIndex: Map<number, StepChange[]>;
  /** Steps no status claimed — rendered at the end of the message */
  unmatched: StepChange[];
}

/**
 * Distributes derived step diffs across a message's status segments, using
 * the steps each status reports having touched.
 *
 * This is the reload path. A live reply pairs diffs to statuses through the
 * streamed snapshots instead, which is exact; here we have only the final
 * workflow, so a step edited by two separate actions appears once, under
 * the last status that touched it.
 *
 * Attribution is by name against `segment.steps`, which Apollo sends as
 * data. A status that reports no steps attracts no diffs — replies from an
 * Apollo that predates the `steps` field simply render their blocks at the
 * end of the message rather than woven in.
 */
/** Mirrors the key the YAML writer derives from a job name */
const hyphenateName = (name: string): string =>
  name.replace(/\s+/g, '-').toLowerCase();

export const assignStepDiffsToStatuses = (
  steps: StepChange[],
  segments: Array<{
    type: string;
    steps?: Array<{ key?: string; name?: string }>;
  }>
): StepDiffAssignment => {
  const byStatusIndex = new Map<number, StepChange[]>();
  const remaining = new Set(steps);
  // A step edited by two actions belongs under the later one: the cumulative
  // diff only reaches the body it shows at the last edit.
  const lastClaim = new Map<StepChange, number>();

  segments.forEach((segment, index) => {
    if (segment.type !== 'status') return;
    if (!segment.steps?.length) return;

    // `key` is the required field on the wire and `name` the optional one, so
    // match on both. The parsed workflow does not keep a job's YAML key, but
    // the writer derives it from the name, so the same transform recovers it.
    const claimed = new Set(
      segment.steps
        .flatMap(step => [step.name?.toLowerCase(), step.key?.toLowerCase()])
        .filter((value): value is string => !!value)
    );
    if (claimed.size === 0) return;

    const matched = steps.filter(
      step =>
        claimed.has(step.name.toLowerCase()) ||
        claimed.has(hyphenateName(step.name))
    );
    matched.forEach(step => {
      lastClaim.set(step, index);
      remaining.delete(step);
    });
  });

  for (const [step, index] of lastClaim) {
    const existing = byStatusIndex.get(index);
    if (existing) existing.push(step);
    else byStatusIndex.set(index, [step]);
  }

  return { byStatusIndex, unmatched: steps.filter(s => remaining.has(s)) };
};

/** A change set pinned to the timeline segment that announced it */
export interface SnapshotChangeSet {
  /** Index of the status segment this change set renders under */
  segmentIndex: number;
  changes: WorkflowChangeSet;
}

/**
 * Derives one change set per streamed snapshot.
 *
 * Apollo emits the workflow YAML every time it actually mutates it, then
 * the settled status describing that mutation. So consecutive snapshots
 * bracket exactly one action, and diffing each against its predecessor
 * gives what that action did — no prose parsing, no name matching.
 *
 * `baselineYaml` is the workflow as it stood when the user sent the
 * message, and is the "before" for the first snapshot. A missing or
 * unparseable baseline is treated as an empty workflow, so the opening
 * action reads as a set of adds rather than rendering nothing.
 *
 * Snapshots that changed nothing are dropped, so a tool call that
 * rewrote the YAML without altering it leaves no empty block behind.
 */
const diffedPairs = new Map<string, WorkflowChangeSet | null>();

/** Change set for one before/after pair, computed once per pair */
const cachedDiff = (
  beforeYaml: string,
  afterYaml: string,
  before: DiffState,
  after: DiffState
): WorkflowChangeSet | null => {
  const key = `${beforeYaml}\u0000${afterYaml}`;
  if (diffedPairs.has(key)) {
    const cached = diffedPairs.get(key) ?? null;
    diffedPairs.delete(key);
    diffedPairs.set(key, cached);
    return cached;
  }

  const changes = diffStates(before, after);
  if (diffedPairs.size >= MAX_CACHED_STATES) {
    const oldest = diffedPairs.keys().next().value;
    if (oldest !== undefined) diffedPairs.delete(oldest);
  }
  diffedPairs.set(key, changes);
  return changes;
};

export const deriveSnapshotChanges = (
  baselineYaml: string | null | undefined,
  snapshots: WorkflowSnapshot[]
): SnapshotChangeSet[] => {
  const out: SnapshotChangeSet[] = [];

  // An unparseable baseline is treated as an empty workflow, the same as a
  // missing one: the opening action then reads as a set of adds rather
  // than silently dropping every diff in the reply.
  let before: DiffState =
    (baselineYaml?.trim() ? tryParseState(baselineYaml) : EMPTY_STATE) ??
    EMPTY_STATE;

  // Keyed on the pair, because this restarts from the baseline every time a
  // new snapshot arrives. Without it K snapshots cost K(K+1)/2 diffs, each
  // running structuredPatch over every changed job body on the main thread
  // while the reply is still streaming.
  let beforeYaml = baselineYaml?.trim() ? baselineYaml : '';

  for (const snapshot of snapshots) {
    const after = tryParseState(snapshot.yaml);
    // Hold the cursor on the last state we could read, so one bad snapshot
    // costs its own block instead of poisoning every snapshot after it.
    if (!after) continue;

    const changes = cachedDiff(beforeYaml, snapshot.yaml, before, after);
    if (changes) {
      out.push({ segmentIndex: snapshot.segmentIndex, changes });
    }
    before = after;
    beforeYaml = snapshot.yaml;
  }

  return out;
};
