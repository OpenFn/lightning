// v2 (CLI-aligned / portability spec) YAML format implementation.
//
// Mirror of `lib/lightning/workflows/yaml_format/v2.ex`. Read
// `test/fixtures/portability/v2/canonical_workflow.yaml` first — that
// fixture is the spec witness; this module must round-trip it.
//
// ## Wire shape
//
// The wire format has a single top-level `steps:` array combining triggers
// and jobs. Trigger steps carry a `type:` discriminator (`webhook` / `cron` /
// `kafka`); job steps don't. Trigger Lightning-specific config lives nested
// under `openfn:` (`cron:`, `cron_cursor:`, `webhook_reply:`, `kafka:`).
//
// | concept                      | v2 field name                |
// |------------------------------|------------------------------|
// | workflow steps array (YAML)  | `steps:` (jobs + triggers)   |
// | trigger discriminator        | `type:`                      |
// | trigger enabled              | `enabled:`                   |
// | step expression / body       | `expression:`                |
// | step adaptor                 | `adaptor:`                   |
// | step credential              | `configuration:`             |
// | trigger Lightning-only state | nested under `openfn:`       |
// | cron expression              | `cron:` (under `openfn:`)    |
// | cron cursor reference        | `cron_cursor:` (under `openfn:`) |
// | webhook reply mode           | `webhook_reply:` (under `openfn:`) |
// | kafka block                  | `kafka:` (under `openfn:`)   |
// | outgoing edges from a node   | `next:` (string or object)   |
// | edge condition               | `condition:`                 |
// | edge JS expression body      | `expression:` (sibling of `condition: js_expression`) |
// | edge label                   | `label:`                     |
// | edge disabled (inverted)     | `disabled:`                  |
//
// `next:` value-shape rule: when a TRIGGER has a single outgoing edge with
// `condition: always` and no other edge fields, the value collapses to the
// bare target step-id string. Job edges always emit the object form. Multiple
// targets always emit a map.

import Ajv from 'ajv';
import YAML from 'yaml';

import { randomUUID } from '../common';

import workflowV2Schema from './schema/workflow-spec-v2.json';
import type {
  Position,
  SpecCronTrigger,
  SpecEdge,
  SpecJob,
  SpecKafkaTrigger,
  SpecTrigger,
  SpecWebhookTrigger,
  StateEdge,
  StateJob,
  StateTrigger,
  WorkflowSpec,
  WorkflowState,
} from './types';
import {
  JobNotFoundError,
  SchemaValidationError,
  TriggerNotFoundError,
  WorkflowError,
  YamlSyntaxError,
  createWorkflowError,
} from './workflow-errors';

// ── Public API ──────────────────────────────────────────────────────────────

export const detectFormat = (parsed: unknown): 'v1' | 'v2' => {
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return 'v1';
  }
  const obj = parsed as Record<string, unknown>;
  const hasSteps = Object.prototype.hasOwnProperty.call(obj, 'steps');
  const hasJobs = Object.prototype.hasOwnProperty.call(obj, 'jobs');
  const hasEdges = Object.prototype.hasOwnProperty.call(obj, 'edges');
  const triggersIsV1Object = isV1TriggersObject(obj['triggers']);

  if (hasSteps && !hasJobs) return 'v2';
  if (hasJobs && hasEdges && triggersIsV1Object) return 'v1';
  if (hasJobs && hasSteps) {
    // eslint-disable-next-line no-console
    console.warn(
      'YamlFormatV2.detectFormat: document has both `jobs:` and `steps:`; treating as v1 (legacy bias)'
    );
    return 'v1';
  }
  // eslint-disable-next-line no-console
  console.warn(
    'YamlFormatV2.detectFormat: ambiguous document (no clear v1/v2 markers); treating as v1 (legacy bias)'
  );
  return 'v1';
};

const isV1TriggersObject = (triggers: unknown): boolean => {
  if (
    triggers === null ||
    typeof triggers !== 'object' ||
    Array.isArray(triggers)
  ) {
    return false;
  }
  return Object.values(triggers as Record<string, unknown>).some(
    v => v !== null && typeof v === 'object' && !Array.isArray(v) && 'type' in v
  );
};

/**
 * Serialize a `WorkflowState` to a v2 YAML string.
 *
 * Triggers and steps are emitted in the order they appear in the input
 * `state.triggers` / `state.jobs` arrays — triggers first, then jobs — into a
 * single unified `steps:` array on the wire.
 */
export const serializeWorkflow = (state: WorkflowState): string => {
  const canonical = workflowStateToCanonical(state);
  return emitCanonicalYaml(canonical);
};

/**
 * Parse a v2 workflow document. Accepts either a YAML string OR a pre-parsed
 * object (so callers that already ran `YAML.parse` after `detectFormat` don't
 * pay for a second parse).
 *
 * Returns a `WorkflowSpec` shaped identically to the v1 parser's output —
 * this is what makes v1 and v2 interchangeable from the caller's view.
 */
export const parseWorkflow = (parsedYaml: unknown): WorkflowSpec => {
  if (typeof parsedYaml === 'string') {
    try {
      parsedYaml = YAML.parse(parsedYaml);
    } catch (error) {
      if (error instanceof Error && error.name === 'YAMLParseError') {
        throw new YamlSyntaxError(error.message, error);
      }
      throw createWorkflowError(error);
    }
  }

  const ajv = new Ajv({ allErrors: true });
  const validate = ajv.compile(workflowV2Schema);
  const isSchemaValid = validate(parsedYaml);
  if (!isSchemaValid && validate.errors) {
    const error = findActionableAjvError(validate.errors);
    if (error) throw new SchemaValidationError(error);
  }

  const parsed = parsedYaml as V2WorkflowDoc;
  return v2DocToWorkflowSpec(parsed);
};

// ── v2 wire-shape types ─────────────────────────────────────────────────────

interface V2EdgeObject {
  condition?: string;
  expression?: string;
  label?: string;
  disabled?: boolean;
}

type V2NextValue = string | Record<string, V2EdgeObject>;

interface V2KafkaConfig {
  hosts?: string[];
  topics?: string[];
  initial_offset_reset_policy?: string;
  connect_timeout?: number;
  group_id?: string;
  sasl?: string;
  ssl?: boolean;
  username?: string;
  password?: string;
  [key: string]: unknown;
}

interface V2OpenfnBlock {
  cron?: string;
  cron_cursor?: string;
  webhook_reply?: 'before_start' | 'after_completion' | 'custom';
  kafka?: V2KafkaConfig;
  [key: string]: unknown;
}

interface V2TriggerStep {
  id: string;
  type: 'webhook' | 'cron' | 'kafka';
  enabled?: boolean;
  openfn?: V2OpenfnBlock;
  next?: V2NextValue;
}

interface V2JobStep {
  id: string;
  name: string;
  adaptor: string;
  expression: string;
  configuration?: string | null;
  next?: V2NextValue;
}

type V2Step = V2TriggerStep | V2JobStep;

interface V2WorkflowDoc {
  name?: string | null;
  steps: V2Step[];
}

const isTriggerStep = (step: V2Step): step is V2TriggerStep => {
  return (
    typeof (step as V2TriggerStep).type === 'string' &&
    ['webhook', 'cron', 'kafka'].includes((step as V2TriggerStep).type)
  );
};

// ── State → v2 canonical map ────────────────────────────────────────────────
//
// The canonical map is the JS object that, when emitted by `emitCanonicalYaml`,
// reproduces the wire-format v2 YAML. It mirrors the parsed-YAML shape exactly.

interface CanonicalEdge {
  condition?: string;
  expression?: string;
  label?: string;
  disabled?: boolean;
}

interface CanonicalTriggerStep {
  id: string;
  type: 'webhook' | 'cron' | 'kafka';
  enabled: boolean;
  openfn?: V2OpenfnBlock;
  next?: string | Record<string, CanonicalEdge>;
}

interface CanonicalJobStep {
  id: string;
  name: string;
  adaptor: string;
  expression: string;
  configuration?: string;
  next?: string | Record<string, CanonicalEdge>;
}

type CanonicalStep = CanonicalTriggerStep | CanonicalJobStep;

interface CanonicalWorkflow {
  name: string;
  steps: CanonicalStep[];
}

const hyphenate = (value: string): string => value.replace(/\s+/g, '-');

const workflowStateToCanonical = (state: WorkflowState): CanonicalWorkflow => {
  const jobIdToKey: Record<string, string> = {};
  state.jobs.forEach(job => {
    jobIdToKey[job.id] = hyphenate(job.name);
  });

  const triggerSteps: CanonicalTriggerStep[] = state.triggers.map(trigger =>
    triggerStateToCanonical(trigger, state.edges, jobIdToKey, state.jobs)
  );

  const jobSteps: CanonicalJobStep[] = state.jobs.map(job =>
    jobStateToCanonical(job, state.edges, jobIdToKey)
  );

  return {
    name: state.name,
    // Trigger steps first, then job steps — matches Elixir's emit order.
    steps: [...triggerSteps, ...jobSteps],
  };
};

const triggerStateToCanonical = (
  trigger: StateTrigger,
  edges: StateEdge[],
  jobIdToKey: Record<string, string>,
  jobs: StateJob[]
): CanonicalTriggerStep => {
  const base: CanonicalTriggerStep = {
    id: trigger.type,
    type: trigger.type,
    enabled: trigger.enabled ?? false,
  };

  const openfn: V2OpenfnBlock = {};
  if (trigger.type === 'cron') {
    if (trigger.cron_expression) openfn.cron = trigger.cron_expression;
    if (trigger.cron_cursor_job_id) {
      const cursorJob = jobs.find(j => j.id === trigger.cron_cursor_job_id);
      if (cursorJob) openfn.cron_cursor = hyphenate(cursorJob.name);
    }
  } else if (trigger.type === 'webhook') {
    if (trigger.webhook_reply) {
      openfn.webhook_reply = trigger.webhook_reply;
    }
  }
  // Kafka: state has no kafka_configuration today; placeholder for parity.

  if (Object.keys(openfn).length > 0) base.openfn = openfn;

  const outgoing = edges.filter(e => e.source_trigger_id === trigger.id);
  const next = buildNextField(
    outgoing,
    jobIdToKey,
    /* collapseToString */ true
  );
  if (next !== undefined) base.next = next;

  return base;
};

const jobStateToCanonical = (
  job: StateJob,
  edges: StateEdge[],
  jobIdToKey: Record<string, string>
): CanonicalJobStep => {
  const base: CanonicalJobStep = {
    id: hyphenate(job.name),
    name: job.name,
    adaptor: job.adaptor,
    expression: job.body,
  };

  // State doesn't carry a credential key directly — the human-readable
  // `<email>|<credential-name>` configuration string is resolved elsewhere
  // (Phase 4 will plumb this through). Round-trip parses preserve it from the
  // YAML when present.

  const outgoing = edges.filter(e => e.source_job_id === job.id);
  // Job edges always emit the object form (no shorthand collapse).
  const next = buildNextField(
    outgoing,
    jobIdToKey,
    /* collapseToString */ false
  );
  if (next !== undefined) base.next = next;

  return base;
};

const buildNextField = (
  edges: StateEdge[],
  jobIdToKey: Record<string, string>,
  collapseToString: boolean
): string | Record<string, CanonicalEdge> | undefined => {
  if (edges.length === 0) return undefined;

  const sorted = [...edges].sort((a, b) => {
    const ak = jobIdToKey[a.target_job_id] ?? '';
    const bk = jobIdToKey[b.target_job_id] ?? '';
    return ak < bk ? -1 : ak > bk ? 1 : 0;
  });

  // Build the object map first.
  const next: Record<string, CanonicalEdge> = {};
  sorted.forEach(edge => {
    const target = jobIdToKey[edge.target_job_id];
    if (!target) return;
    next[target] = edgeToCanonical(edge);
  });

  // Single-target `:always` collapse — only for triggers.
  if (collapseToString) {
    const keys = Object.keys(next);
    if (keys.length === 1) {
      const key = keys[0]!;
      const edge = next[key]!;
      const isAlwaysOnly =
        edge.condition === 'always' && Object.keys(edge).length === 1;
      if (isAlwaysOnly) return key;
    }
  }

  return next;
};

const edgeToCanonical = (edge: StateEdge): CanonicalEdge => {
  const out: CanonicalEdge = {};
  out.condition = edge.condition_type || 'always';
  if (edge.condition_type === 'js_expression' && edge.condition_expression) {
    out.expression = edge.condition_expression;
  }
  if (edge.condition_label) out.label = edge.condition_label;
  if (edge.enabled === false) out.disabled = true;
  return out;
};

// ── Canonical map → YAML string ─────────────────────────────────────────────
//
// We use the `yaml` package's Document AST and a Scalar visitor to apply
// Elixir's `quote_if_needed` rule: identifier-like strings stay plain; anything
// containing colons, quotes, special chars, or YAML reserved keywords gets
// single-quoted; multiline strings become block literals.

const RESERVED_YAML = new Set([
  'true',
  'false',
  'null',
  'yes',
  'no',
  'on',
  'off',
  '~',
]);

const needsQuoting = (s: string): boolean => {
  if (s === '') return true;
  if (RESERVED_YAML.has(s.toLowerCase())) return true;
  // Mirrors `Lightning.Workflows.YamlFormat.V2.quote_if_needed/1`:
  // ^[A-Za-z0-9][A-Za-z0-9_\-@./> ]*[A-Za-z0-9]$  (and not reserved)
  return !/^[A-Za-z0-9][A-Za-z0-9_\-@./> ]*[A-Za-z0-9]$/.test(s);
};

const emitCanonicalYaml = (workflow: CanonicalWorkflow): string => {
  // Strip undefined values; preserve key order via the order we constructed
  // the canonical structures.
  const cleaned = stripUndefined(workflow);

  const doc = new YAML.Document(cleaned);

  YAML.visit(doc, {
    Scalar(_key, node) {
      if (typeof node.value === 'string') {
        if (node.value.includes('\n')) {
          node.type = 'BLOCK_LITERAL';
        } else if (needsQuoting(node.value)) {
          node.type = 'QUOTE_SINGLE';
        } else {
          node.type = 'PLAIN';
        }
      }
    },
  });

  return doc.toString({ lineWidth: 0, blockQuote: 'literal' });
};

const stripUndefined = <T>(value: T): T => {
  if (Array.isArray(value)) {
    return value.map(v => stripUndefined(v)) as unknown as T;
  }
  if (value !== null && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    Object.entries(value as Record<string, unknown>).forEach(([k, v]) => {
      if (v === undefined) return;
      out[k] = stripUndefined(v);
    });
    return out as T;
  }
  return value;
};

// ── v2 doc → WorkflowSpec ───────────────────────────────────────────────────
//
// The downstream `convertWorkflowSpecToState` (v1) understands the v1-shaped
// `WorkflowSpec` keyed by hyphenated step name. We split the unified
// `steps:` array into the v1 trigger/job/edge maps so the rest of the import
// pipeline stays format-agnostic.

const v2DocToWorkflowSpec = (doc: V2WorkflowDoc): WorkflowSpec => {
  const triggerSteps: V2TriggerStep[] = [];
  const jobSteps: V2JobStep[] = [];

  doc.steps.forEach(step => {
    if (isTriggerStep(step)) {
      triggerSteps.push(step);
    } else {
      jobSteps.push(step as V2JobStep);
    }
  });

  // Build the set of valid step ids (both triggers and jobs) for next-ref
  // dangling-target checks below.
  const stepIds = new Set<string>([
    ...triggerSteps.map(s => s.id),
    ...jobSteps.map(s => s.id),
  ]);

  const triggers: Record<string, SpecTrigger> = {};
  triggerSteps.forEach(trigger => {
    triggers[trigger.id] = v2TriggerStepToSpecTrigger(trigger);
  });

  const jobs: Record<string, SpecJob> = {};
  jobSteps.forEach(step => {
    const job: SpecJob & { credential?: string } = {
      name: step.name,
      adaptor: step.adaptor,
      body: step.expression,
      pos: undefined as unknown as Position | undefined,
    };
    if (step.configuration) {
      job.credential = step.configuration;
    }
    jobs[step.id] = job;
  });

  const edges: Record<string, SpecEdge> = {};

  // Trigger-sourced edges (next: on a trigger step).
  triggerSteps.forEach(trigger => {
    if (!trigger.next) return;
    iterateNext(trigger.next, (target, edgeObj) => {
      if (!stepIds.has(target)) {
        throw new JobNotFoundError(target, `${trigger.id}->${target}`, false);
      }
      edges[`${trigger.id}->${target}`] = nextEntryToSpecEdge(
        { fromTrigger: trigger.id },
        target,
        edgeObj
      );
    });
  });

  // Step-sourced edges (next: on a job step).
  jobSteps.forEach(step => {
    if (!step.next) return;
    iterateNext(step.next, (target, edgeObj) => {
      if (!stepIds.has(target)) {
        throw new JobNotFoundError(target, `${step.id}->${target}`, false);
      }
      edges[`${step.id}->${target}`] = nextEntryToSpecEdge(
        { fromJob: step.id },
        target,
        edgeObj
      );
    });
  });

  const spec: WorkflowSpec = {
    name: doc.name ?? '',
    jobs,
    triggers,
    edges,
  };
  return spec;
};

const v2TriggerStepToSpecTrigger = (trigger: V2TriggerStep): SpecTrigger => {
  const enabled = trigger.enabled ?? true;
  const openfn = trigger.openfn ?? {};

  if (trigger.type === 'cron') {
    const out: SpecCronTrigger = {
      type: 'cron',
      enabled,
      cron_expression: openfn.cron ?? '',
      cron_cursor_job: openfn.cron_cursor ?? null,
      pos: undefined,
    };
    return out;
  }
  if (trigger.type === 'webhook') {
    const out: SpecWebhookTrigger = {
      type: 'webhook',
      enabled,
      webhook_reply: openfn.webhook_reply ?? null,
      pos: undefined,
    };
    return out;
  }
  const out: SpecKafkaTrigger = {
    type: 'kafka',
    enabled,
  };
  return out;
};

const iterateNext = (
  next: V2NextValue,
  cb: (target: string, edge: V2EdgeObject) => void
): void => {
  if (typeof next === 'string') {
    // Single-target shorthand: bare target id ⇒ implicit `condition: always`.
    cb(next, { condition: 'always' });
    return;
  }
  Object.entries(next).forEach(([target, edge]) => cb(target, edge));
};

const nextEntryToSpecEdge = (
  source: { fromTrigger?: string; fromJob?: string },
  target: string,
  edge: V2EdgeObject
): SpecEdge => {
  const out: SpecEdge = {
    target_job: target,
    condition_type: edge.condition ?? 'always',
    // v2 wire field is `disabled:` (defaults false). v1/SpecEdge uses the
    // inverted `enabled` boolean.
    enabled: edge.disabled === true ? false : true,
  };
  if (source.fromTrigger) out.source_trigger = source.fromTrigger;
  if (source.fromJob) out.source_job = source.fromJob;
  if (edge.label) out.condition_label = edge.label;
  if (edge.expression) out.condition_expression = edge.expression;
  return out;
};

// ── helpers ─────────────────────────────────────────────────────────────────

interface AjvErrorObject {
  keyword: string;
  instancePath: string;
  params: Record<string, unknown>;
  message?: string;
}

const findActionableAjvError = (
  errors: AjvErrorObject[]
): AjvErrorObject | undefined => {
  const requiredError = errors.find(e => e.keyword === 'required');
  const additionalPropertiesError = errors.find(
    e => e.keyword === 'additionalProperties'
  );
  const typeError = errors.find(e => e.keyword === 'type');
  const enumError = errors.find(e => e.keyword === 'enum');
  return (
    enumError ||
    additionalPropertiesError ||
    requiredError ||
    typeError ||
    errors[0]
  );
};

// Re-exported so callers can construct fresh ids for synthesized records
// without pulling in `../common`.
export { randomUUID };

// Re-exported so error classes are available from the v2 module surface.
export {
  JobNotFoundError,
  SchemaValidationError,
  TriggerNotFoundError,
  WorkflowError,
  YamlSyntaxError,
};
