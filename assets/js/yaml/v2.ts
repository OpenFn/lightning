// v2 (portability spec) YAML format implementation.
//
// Mirror of `lib/lightning/workflows/yaml_format/v2.ex`. Read
// `test/fixtures/portability/v2/canonical_workflow.yaml` first — that
// fixture is the spec witness; this module must round-trip it.
//
// Spec source: https://raw.githubusercontent.com/OpenFn/kit/42d6b38/packages/lexicon/portability.d.ts
//
// ## Wire shape (workflow)
//
// `steps: Array<Job | Trigger>` — single top-level array combining triggers
// and jobs. Jobs use `adaptor: string` (singular). Triggers carry
// `cron_expression?` and `webhook_reply?` as flat spec-defined fields.
// Lightning-specific extensions (`cron_cursor`, `kafka`) live under
// `openfn:` since the spec doesn't define them.
//
// ## Edge shape (`next:`)
//
// Spec: `next?: string | Record<StepId, StepEdge>` where
// `StepEdge = boolean | string | ConditionalStepEdge` and
// `ConditionalStepEdge = { condition?: string /* JS body */, label?, disabled? }`.
//
// Lightning's internal `condition_type` enum maps to canonical JS strings:
//   :always           → omit `condition` (or boolean true shortcut)
//   :on_job_success   → `condition: '!state.errors'`
//   :on_job_failure   → `condition: '!!state.errors'`
//   :js_expression    → `condition: <user JS body>`
//
// On parse the canonical strings are matched verbatim to round-trip back to
// the original `condition_type`. Anything else under `condition` is treated
// as a `:js_expression` body. Boolean `true` is `:always`; boolean `false`
// becomes `:js_expression` with body "false" (Lightning has no `never`).
//
// `next:` collapse: when a step has a single unconditional outgoing edge
// (no condition / label / disabled), the value collapses to the bare target
// id string. Multi-target or non-:always edges always emit the object form.

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
  StateKafkaConfiguration,
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
  label?: string;
  disabled?: boolean;
}

// Spec: `StepEdge = boolean | string | ConditionalStepEdge`.
type V2StepEdge = boolean | string | V2EdgeObject;

type V2NextValue = string | Record<string, V2StepEdge>;

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

/**
 * DEPRECATED legacy nested extension block. Lightning now emits `cron_cursor`
 * and kafka config fields flat at the trigger root. Kept here as an
 * accepted-on-parse shape so externally-authored v2 documents that still use
 * the old form keep working.
 */
interface V2OpenfnBlock {
  cron_cursor?: string;
  kafka?: V2KafkaConfig;
  [key: string]: unknown;
}

interface V2TriggerStep extends V2KafkaConfig {
  id: string;
  name?: string;
  type: 'webhook' | 'cron' | 'kafka';
  enabled?: boolean;
  cron_expression?: string;
  cron_cursor?: string;
  webhook_reply?: string;
  /** DEPRECATED: legacy openfn extension block. See `V2OpenfnBlock`. */
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
  id?: string;
  name?: string | null;
  /** Spec: WorkflowSpec.start — the entry trigger's step-id. Optional on parse. */
  start?: string;
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
  label?: string;
  disabled?: boolean;
}

interface CanonicalTriggerStep extends V2KafkaConfig {
  id: string;
  name: string;
  type: 'webhook' | 'cron' | 'kafka';
  enabled: boolean;
  cron_expression?: string;
  cron_cursor?: string;
  webhook_reply?: string;
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
  id: string;
  name: string;
  start?: string;
  steps: CanonicalStep[];
}

const hyphenate = (value: string): string => value.replace(/\s+/g, '-');

// Kafka config travels flat on the trigger root in YAML
// (`hosts: [...]`, `topics: [...]`, `connect_timeout: …`, etc.) — matches
// `lib/lightning/workflows/yaml_format/v2.ex:kafka_config_to_canonical/1`.
//
// On state the same data lives under `kafka_configuration` with `_string`
// forms for hosts/topics (as it ships from Y.Doc).
const splitCsv = (s: string | null | undefined): string[] =>
  (s ?? '')
    .split(',')
    .map(part => part.trim())
    .filter(Boolean);

const kafkaConfigToCanonical = (
  config: StateKafkaConfiguration
): V2KafkaConfig => {
  const out: V2KafkaConfig = {};
  const hosts = splitCsv(config.hosts_string);
  if (hosts.length) out.hosts = hosts;
  const topics = splitCsv(config.topics_string);
  if (topics.length) out.topics = topics;
  if (config.initial_offset_reset_policy) {
    out.initial_offset_reset_policy = config.initial_offset_reset_policy;
  }
  if (typeof config.connect_timeout === 'number') {
    out.connect_timeout = config.connect_timeout;
  }
  if (config.group_id) out.group_id = config.group_id;
  if (config.sasl) out.sasl = config.sasl;
  if (typeof config.ssl === 'boolean') out.ssl = config.ssl;
  if (config.username) out.username = config.username;
  if (config.password) out.password = config.password;
  return out;
};

const kafkaConfigFromCanonical = (
  trigger: V2TriggerStep
): StateKafkaConfiguration | null => {
  const fromOpenfn = trigger.openfn?.kafka ?? {};
  const hosts = trigger.hosts ?? fromOpenfn.hosts ?? [];
  const topics = trigger.topics ?? fromOpenfn.topics ?? [];
  const policy =
    trigger.initial_offset_reset_policy ??
    fromOpenfn.initial_offset_reset_policy;
  const timeout = trigger.connect_timeout ?? fromOpenfn.connect_timeout;

  // If nothing kafka-shaped is on the trigger, leave it null so callers can
  // distinguish "no config emitted" from "config emitted but empty".
  if (
    hosts.length === 0 &&
    topics.length === 0 &&
    policy === undefined &&
    timeout === undefined
  ) {
    return null;
  }

  const out: StateKafkaConfiguration = {
    hosts_string: hosts.join(', '),
    topics_string: topics.join(', '),
    initial_offset_reset_policy: policy ?? 'latest',
    connect_timeout: typeof timeout === 'number' ? timeout : 30,
  };
  const groupId = trigger.group_id ?? fromOpenfn.group_id;
  if (groupId) out.group_id = groupId;
  const sasl = trigger.sasl ?? fromOpenfn.sasl;
  if (sasl) out.sasl = sasl;
  const ssl = trigger.ssl ?? fromOpenfn.ssl;
  if (typeof ssl === 'boolean') out.ssl = ssl;
  const username = trigger.username ?? fromOpenfn.username;
  if (username) out.username = username;
  const password = trigger.password ?? fromOpenfn.password;
  if (password) out.password = password;
  return out;
};

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

  // Spec: WorkflowSpec.start is the entry trigger's step-id. Lightning
  // workflows are single-trigger in practice; we take the first trigger.
  const start = triggerSteps[0]?.id;

  return {
    id: hyphenate(state.name),
    name: state.name,
    ...(start ? { start } : {}),
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
    name: trigger.type,
    type: trigger.type,
    enabled: trigger.enabled ?? false,
  };

  // Spec-defined flat fields go on the trigger itself.
  if (trigger.type === 'cron' && trigger.cron_expression) {
    base.cron_expression = trigger.cron_expression;
  } else if (trigger.type === 'webhook' && trigger.webhook_reply) {
    base.webhook_reply = trigger.webhook_reply;
  }

  // Lightning extension fields live flat at the trigger root (matches the
  // Elixir emitter at `lib/lightning/workflows/yaml_format/v2.ex`). The spec's
  // Trigger interface doesn't forbid extra fields and the kitchen-sink
  // example uses the flat form.
  if (trigger.type === 'cron' && trigger.cron_cursor_job_id) {
    const cursorJob = jobs.find(j => j.id === trigger.cron_cursor_job_id);
    if (cursorJob) base.cron_cursor = hyphenate(cursorJob.name);
  }
  if (trigger.type === 'kafka' && trigger.kafka_configuration) {
    Object.assign(base, kafkaConfigToCanonical(trigger.kafka_configuration));
  }

  const outgoing = edges.filter(e => e.source_trigger_id === trigger.id);
  const next = buildNextField(outgoing, jobIdToKey);
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
    // Spec: `adaptor?: string` (singular).
    adaptor: job.adaptor ?? '',
    expression: job.body,
  };

  const outgoing = edges.filter(e => e.source_job_id === job.id);
  const next = buildNextField(outgoing, jobIdToKey);
  if (next !== undefined) base.next = next;

  return base;
};

const buildNextField = (
  edges: StateEdge[],
  jobIdToKey: Record<string, string>
): Record<string, CanonicalEdge> | undefined => {
  if (edges.length === 0) return undefined;

  const sorted = [...edges].sort((a, b) => {
    const ak = jobIdToKey[a.target_job_id] ?? '';
    const bk = jobIdToKey[b.target_job_id] ?? '';
    return ak < bk ? -1 : ak > bk ? 1 : 0;
  });

  // Build the object map. Verbose-only emission per
  // `portability.d.ts:60` (`// TODO remove next: string`) and to avoid the
  // bare-string parsing bug in @openfn/project@0.15.
  const next: Record<string, CanonicalEdge> = {};
  sorted.forEach(edge => {
    const target = jobIdToKey[edge.target_job_id];
    if (!target) return;
    next[target] = edgeToCanonical(edge);
  });

  return next;
};

// Map Lightning's `condition_type` enum to the wire-format condition value.
// Per `lightning.d.ts:102` the spec accepts the union
// `'always' | 'on_job_success' | 'on_job_failure' | string`. We emit the
// literal verbatim for all three named values (matching the kitchen-sink
// example) and the user JS body for js_expression. The condition is always
// present in the verbose `next:` form, so downstream parsers don't need a
// default for missing values.
const edgeConditionValue = (edge: StateEdge): string | undefined => {
  switch (edge.condition_type) {
    case 'js_expression':
      return edge.condition_expression || undefined;
    case 'on_job_success':
      return 'on_job_success';
    case 'on_job_failure':
      return 'on_job_failure';
    case 'always':
      return 'always';
    default:
      return undefined;
  }
};

const edgeToCanonical = (edge: StateEdge): CanonicalEdge => {
  const out: CanonicalEdge = {};
  const condition = edgeConditionValue(edge);
  if (condition !== undefined) out.condition = condition;
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
    // Spec: `adaptor?: string` (singular). Read it directly into Lightning's
    // single-adaptor state field.
    const job: SpecJob & { credential?: string } = {
      name: step.name,
      adaptor: step.adaptor ?? '',
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
  // Backwards-compat: accept the legacy `openfn: { cron_cursor }` shape from
  // older v2 documents that haven't been re-emitted yet. New documents emit
  // `cron_cursor:` flat at the trigger root.
  const openfn = trigger.openfn ?? {};

  if (trigger.type === 'cron') {
    const out: SpecCronTrigger = {
      type: 'cron',
      enabled,
      cron_expression: trigger.cron_expression ?? '',
      cron_cursor_job: trigger.cron_cursor ?? openfn.cron_cursor ?? null,
      pos: undefined,
    };
    return out;
  }
  if (trigger.type === 'webhook') {
    const out: SpecWebhookTrigger = {
      type: 'webhook',
      enabled,
      webhook_reply: trigger.webhook_reply ?? null,
      pos: undefined,
    };
    return out;
  }
  const kafka_configuration = kafkaConfigFromCanonical(trigger);
  const out: SpecKafkaTrigger = {
    type: 'kafka',
    enabled,
    ...(kafka_configuration ? { kafka_configuration } : {}),
  };
  return out;
};

const iterateNext = (
  next: V2NextValue,
  cb: (target: string, edge: V2EdgeObject) => void
): void => {
  if (typeof next === 'string') {
    // Bare target id ⇒ unconditional edge (spec: `next: <step-id>`).
    cb(next, {});
    return;
  }
  Object.entries(next).forEach(([target, value]) => {
    if (value === true) {
      // Boolean shortcut: `next: { foo: true }` ⇒ unconditional edge.
      cb(target, {});
    } else if (value === false) {
      // Boolean false ⇒ never-firing edge. Lightning has no `:never` enum,
      // so we round-trip via a `:js_expression` body of "false".
      cb(target, { condition: 'false' });
    } else if (typeof value === 'string') {
      // String shortcut: `next: { foo: "<js>" }` ⇒ ConditionalStepEdge with
      // only the `condition` field.
      cb(target, { condition: value });
    } else {
      cb(target, value);
    }
  });
};

// Per `lightning.d.ts:102`, `condition` is the union
// `'always' | 'on_job_success' | 'on_job_failure' | string`. Map the three
// named literals back to Lightning's `condition_type` enum; anything else
// (including legacy `'!state.errors'` JS-body emissions from older v2
// documents) is treated as a JS expression body.
const conditionTypeFromValue = (
  condition: string | undefined
): { condition_type: string; condition_expression?: string } => {
  if (condition === undefined || condition === '') {
    return { condition_type: 'always' };
  }
  // Strip a single trailing newline so block-literal bodies match the inline
  // canonical strings (`yaml` parses `|` blocks with a trailing `\n`).
  const trimmed = condition.replace(/\n$/, '');

  // Named literals from the spec union.
  if (trimmed === 'always') return { condition_type: 'always' };
  if (trimmed === 'on_job_success') return { condition_type: 'on_job_success' };
  if (trimmed === 'on_job_failure') return { condition_type: 'on_job_failure' };

  // Backwards-compat: Lightning previously emitted these JS bodies for the
  // named conditions. Accept them so older v2 documents in the wild keep
  // round-tripping cleanly.
  if (trimmed === '!state.errors') return { condition_type: 'on_job_success' };
  if (trimmed === '!!state.errors') return { condition_type: 'on_job_failure' };

  return {
    condition_type: 'js_expression',
    condition_expression: condition,
  };
};

const nextEntryToSpecEdge = (
  source: { fromTrigger?: string; fromJob?: string },
  target: string,
  edge: V2EdgeObject
): SpecEdge => {
  const { condition_type, condition_expression } = conditionTypeFromValue(
    edge.condition
  );

  const out: SpecEdge = {
    target_job: target,
    condition_type,
    // v2 wire field is `disabled:` (defaults false). v1/SpecEdge uses the
    // inverted `enabled` boolean.
    enabled: edge.disabled === true ? false : true,
  };
  if (source.fromTrigger) out.source_trigger = source.fromTrigger;
  if (source.fromJob) out.source_job = source.fromJob;
  if (edge.label) out.condition_label = edge.label;
  if (condition_expression !== undefined) {
    out.condition_expression = condition_expression;
  }
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
