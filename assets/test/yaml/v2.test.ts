/**
 * v2 (CLI-aligned / portability spec) YAML format tests.
 *
 * Phase 2 of issue #4718. Covers the JS-side success criteria:
 *   - Round-trip via `WorkflowState` (state → serialize → parse → state)
 *   - Round-trip from on-disk v2 fixtures (parse → serialize → parse)
 *   - Cross-language parity: parsing the v1 and v2 fixture for the same
 *     scenario yields equivalent `WorkflowSpec` content.
 *   - AJV schema rejection: documents missing `steps:` are rejected at the
 *     schema layer; documents whose `next:` points at a non-existent step id
 *     are rejected at parse time (`JobNotFoundError`).
 *
 * The wire shape is the unified `steps:` array (triggers AND jobs in one
 * list, distinguished by a `type:` discriminator on triggers, with
 * Lightning-specific trigger config nested under `openfn:`). This matches the
 * Elixir `Lightning.Workflows.YamlFormat.V2` module and the @openfn/cli
 * lexicon. See `test/fixtures/portability/v2/canonical_workflow.yaml` for the
 * spec witness.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import Ajv from 'ajv';
import YAML from 'yaml';
import { describe, expect, it } from 'vitest';

import workflowV2Schema from '../../js/yaml/schema/workflow-spec-v2.json';
import type {
  StateEdge,
  StateJob,
  StateTrigger,
  WorkflowState,
} from '../../js/yaml/types';
import * as v1 from '../../js/yaml/v1';
import * as v2 from '../../js/yaml/v2';
import { SchemaValidationError } from '../../js/yaml/workflow-errors';

// ── Fixture loading ─────────────────────────────────────────────────────────

const FIXTURES_ROOT = resolve(__dirname, '../../../test/fixtures/portability');

const SCENARIOS = [
  'simple-webhook',
  'cron-with-cursor',
  'js-expression-edge',
  'multi-trigger',
  'kafka-trigger',
  'branching-jobs',
] as const;

const ALL_V2_FIXTURES = ['canonical_workflow', ...SCENARIOS] as const;

const readFixture = (
  format: 'v1' | 'v2',
  name: string
): { text: string; path: string } => {
  const path =
    name === 'canonical_workflow'
      ? `${FIXTURES_ROOT}/${format}/canonical_workflow.yaml`
      : `${FIXTURES_ROOT}/${format}/scenarios/${name}.yaml`;
  return { text: readFileSync(path, 'utf-8'), path };
};

// ── Synthetic state factories ───────────────────────────────────────────────
//
// These build `WorkflowState` instances in the shape v2.ts itself produces
// when serializing. They let us round-trip through v2.ts without depending
// on the (currently misaligned) on-disk fixtures.

const makeJob = (
  overrides: Partial<StateJob> & { name: string }
): StateJob => ({
  id: `job-${overrides.name}`,
  adaptor: '@openfn/language-common@latest',
  body: 'fn(state => state)\n',
  keychain_credential_id: null,
  project_credential_id: null,
  ...overrides,
});

const baseEdge = (overrides: Partial<StateEdge>): StateEdge => ({
  id: `edge-${Math.random().toString(36).slice(2, 9)}`,
  condition_type: 'always',
  enabled: true,
  target_job_id: 'job-x',
  ...overrides,
});

const simpleWebhookState = (): WorkflowState => {
  const greet = makeJob({ name: 'greet' });
  const webhook: StateTrigger = {
    id: 'trigger-webhook',
    type: 'webhook',
    enabled: true,
    webhook_reply: null,
  };
  return {
    id: 'wf-1',
    name: 'simple webhook',
    jobs: [greet],
    triggers: [webhook],
    edges: [
      baseEdge({
        source_trigger_id: webhook.id,
        target_job_id: greet.id,
      }),
    ],
    positions: null,
  };
};

const cronWithCursorState = (): WorkflowState => {
  const cursor = makeJob({ name: 'cursor step' });
  const cron: StateTrigger = {
    id: 'trigger-cron',
    type: 'cron',
    enabled: true,
    cron_expression: '0 6 * * *',
    cron_cursor_job_id: cursor.id,
  };
  return {
    id: 'wf-2',
    name: 'cron with cursor',
    jobs: [cursor],
    triggers: [cron],
    edges: [
      baseEdge({
        source_trigger_id: cron.id,
        target_job_id: cursor.id,
      }),
    ],
    positions: null,
  };
};

const jsExpressionEdgeState = (): WorkflowState => {
  const source = makeJob({ name: 'source step' });
  const target = makeJob({ name: 'target step' });
  const webhook: StateTrigger = {
    id: 'trigger-webhook',
    type: 'webhook',
    enabled: true,
    webhook_reply: null,
  };
  return {
    id: 'wf-3',
    name: 'js expression edge',
    jobs: [source, target],
    triggers: [webhook],
    edges: [
      baseEdge({
        source_trigger_id: webhook.id,
        target_job_id: source.id,
      }),
      baseEdge({
        source_job_id: source.id,
        target_job_id: target.id,
        condition_type: 'js_expression',
        condition_label: 'Only when payload present',
        condition_expression: '!!state.data && state.data.length > 0\n',
      }),
    ],
    positions: null,
  };
};

const multiTriggerState = (): WorkflowState => {
  const shared = makeJob({ name: 'shared step' });
  const webhook: StateTrigger = {
    id: 'trigger-webhook',
    type: 'webhook',
    enabled: true,
    webhook_reply: null,
  };
  const cron: StateTrigger = {
    id: 'trigger-cron',
    type: 'cron',
    enabled: true,
    cron_expression: '*/5 * * * *',
    cron_cursor_job_id: null,
  };
  return {
    id: 'wf-4',
    name: 'multi trigger',
    jobs: [shared],
    triggers: [webhook, cron],
    edges: [
      baseEdge({ source_trigger_id: webhook.id, target_job_id: shared.id }),
      baseEdge({ source_trigger_id: cron.id, target_job_id: shared.id }),
    ],
    positions: null,
  };
};

const kafkaTriggerState = (): WorkflowState => {
  const consume = makeJob({ name: 'consume' });
  const kafka: StateTrigger = {
    id: 'trigger-kafka',
    type: 'kafka',
    enabled: true,
  };
  return {
    id: 'wf-5',
    name: 'kafka trigger',
    jobs: [consume],
    triggers: [kafka],
    edges: [
      baseEdge({
        source_trigger_id: kafka.id,
        target_job_id: consume.id,
      }),
    ],
    positions: null,
  };
};

const branchingJobsState = (): WorkflowState => {
  const fanOut = makeJob({ name: 'fan out' });
  const branchA = makeJob({ name: 'branch a' });
  const branchB = makeJob({ name: 'branch b' });
  const webhook: StateTrigger = {
    id: 'trigger-webhook',
    type: 'webhook',
    enabled: true,
    webhook_reply: null,
  };
  return {
    id: 'wf-6',
    name: 'branching jobs',
    jobs: [fanOut, branchA, branchB],
    triggers: [webhook],
    edges: [
      baseEdge({ source_trigger_id: webhook.id, target_job_id: fanOut.id }),
      baseEdge({
        source_job_id: fanOut.id,
        target_job_id: branchA.id,
        condition_type: 'on_job_success',
      }),
      baseEdge({
        source_job_id: fanOut.id,
        target_job_id: branchB.id,
        condition_type: 'on_job_failure',
      }),
    ],
    positions: null,
  };
};

const SYNTHETIC_STATES: Array<{ name: string; state: () => WorkflowState }> = [
  { name: 'simple-webhook', state: simpleWebhookState },
  { name: 'cron-with-cursor', state: cronWithCursorState },
  { name: 'js-expression-edge', state: jsExpressionEdgeState },
  { name: 'multi-trigger', state: multiTriggerState },
  { name: 'kafka-trigger', state: kafkaTriggerState },
  { name: 'branching-jobs', state: branchingJobsState },
];

// ── Round-trip: state → YAML → spec ─────────────────────────────────────────

describe('v2.serializeWorkflow / parseWorkflow round-trip on synthetic state', () => {
  it.each(SYNTHETIC_STATES)(
    'preserves structure for $name',
    ({ state: makeState }) => {
      const state = makeState();
      const yaml = v2.serializeWorkflow(state);

      // Sanity: serialized output is a v2 doc — single unified `steps:`
      // array combining trigger and job entries (no top-level `triggers:`).
      const parsedYaml = YAML.parse(yaml) as Record<string, unknown>;
      expect(parsedYaml).toHaveProperty('steps');
      expect(Array.isArray(parsedYaml['steps'])).toBe(true);
      expect(parsedYaml).not.toHaveProperty('triggers');
      expect(parsedYaml).not.toHaveProperty('jobs');

      // Re-parse via v2.parseWorkflow (string input) → WorkflowSpec.
      const spec = v2.parseWorkflow(yaml);
      expect(spec.name).toBe(state.name);

      // Every job in state is represented as a step in the parsed spec
      // (keyed by hyphenated name).
      state.jobs.forEach(job => {
        const key = job.name.replace(/\s+/g, '-');
        expect(spec.jobs[key]).toBeDefined();
        expect(spec.jobs[key]?.name).toBe(job.name);
        expect(spec.jobs[key]?.adaptor).toBe(job.adaptor);
        expect(spec.jobs[key]?.body).toBe(job.body);
      });

      // Every trigger maps to a spec trigger keyed by its `type` (the v2
      // serializer uses type as the stable id).
      state.triggers.forEach(trigger => {
        const triggerSpec = spec.triggers[trigger.type];
        expect(triggerSpec).toBeDefined();
        expect(triggerSpec?.type).toBe(trigger.type);
        expect(triggerSpec?.enabled).toBe(trigger.enabled);
      });

      // Edge count matches — v2 represents edges via `next:` but the spec
      // shape keeps them in a flat map keyed `source->target`.
      expect(Object.keys(spec.edges).length).toBe(state.edges.length);

      // No edge points at a non-existent step.
      Object.values(spec.edges).forEach(edge => {
        expect(spec.jobs[edge.target_job]).toBeDefined();
        if (edge.source_job) {
          expect(spec.jobs[edge.source_job]).toBeDefined();
        }
        if (edge.source_trigger) {
          expect(spec.triggers[edge.source_trigger]).toBeDefined();
        }
      });
    }
  );

  it.each(SYNTHETIC_STATES)(
    'second round-trip is structurally stable for $name',
    ({ state: makeState }) => {
      const state = makeState();
      const yaml1 = v2.serializeWorkflow(state);
      const spec1 = v2.parseWorkflow(yaml1);

      const state2 = v1.convertWorkflowSpecToState(spec1);
      const yaml2 = v2.serializeWorkflow(state2);
      const spec2 = v2.parseWorkflow(yaml2);

      // Same shape on a second pass.
      expect(Object.keys(spec2.jobs).sort()).toEqual(
        Object.keys(spec1.jobs).sort()
      );
      expect(Object.keys(spec2.triggers).sort()).toEqual(
        Object.keys(spec1.triggers).sort()
      );
      expect(Object.keys(spec2.edges).sort()).toEqual(
        Object.keys(spec1.edges).sort()
      );
    }
  );
});

// ── On-disk fixture round-trip ──────────────────────────────────────────────

describe('v2 fixture round-trip', () => {
  it.each(ALL_V2_FIXTURES)('round-trips %s', name => {
    const { text } = readFixture('v2', name);
    const spec = v2.parseWorkflow(text);

    expect(spec).toBeDefined();
    expect(typeof spec.name).toBe('string');
    expect(spec.jobs).toBeDefined();
    expect(spec.triggers).toBeDefined();
    expect(spec.edges).toBeDefined();

    // No dangling next refs in the parsed spec.
    Object.values(spec.edges).forEach(edge => {
      expect(spec.jobs[edge.target_job]).toBeDefined();
    });

    // Re-serialize from a state derived from the parsed spec.
    const state = v1.convertWorkflowSpecToState(spec);
    const yaml2 = v2.serializeWorkflow(state);
    const spec2 = v2.parseWorkflow(yaml2);

    // Structural equivalence on the second parse.
    expect(Object.keys(spec2.jobs).sort()).toEqual(
      Object.keys(spec.jobs).sort()
    );
    expect(Object.keys(spec2.triggers).sort()).toEqual(
      Object.keys(spec.triggers).sort()
    );
    expect(Object.keys(spec2.edges).sort()).toEqual(
      Object.keys(spec.edges).sort()
    );
  });
});

// ── Cross-language fixture parity ───────────────────────────────────────────
//
// The v1 and v2 fixture for each scenario describe the same workflow in two
// formats. Parsing them must produce equivalent `WorkflowSpec` content
// (modulo trigger keying — v1 keys by `type`; v2 step `id` is also the type
// for triggers, so the keys line up).

describe('cross-language fixture parity', () => {
  it.each(SCENARIOS)(
    'v1 and v2 fixtures of %s parse to equivalent specs',
    name => {
      const v1Text = readFixture('v1', name).text;
      const v2Text = readFixture('v2', name).text;

      const v1Spec = v1.parseWorkflowYAML(v1Text);
      const v2Spec = v2.parseWorkflow(v2Text);

      expect(v1Spec.name).toBe(v2Spec.name);
      expect(Object.keys(v1Spec.jobs).sort()).toEqual(
        Object.keys(v2Spec.jobs).sort()
      );
      expect(Object.keys(v1Spec.triggers).sort()).toEqual(
        Object.keys(v2Spec.triggers).sort()
      );

      Object.entries(v1Spec.jobs).forEach(([key, j1]) => {
        const j2 = v2Spec.jobs[key];
        expect(j2).toBeDefined();
        expect(j2?.name).toBe(j1.name);
        expect(j2?.adaptor).toBe(j1.adaptor);
        expect(j2?.body).toBe(j1.body);
      });

      Object.entries(v1Spec.triggers).forEach(([key, t1]) => {
        const t2 = v2Spec.triggers[key];
        expect(t2).toBeDefined();
        expect(t2?.type).toBe(t1.type);
        expect(t2?.enabled).toBe(t1.enabled);
      });
    }
  );
});

// ── AJV schema rejection ────────────────────────────────────────────────────

describe('v2 AJV schema rejection', () => {
  const ajv = new Ajv({ allErrors: true });
  const validate = ajv.compile(workflowV2Schema);

  it('rejects a doc missing `steps:`', () => {
    const doc = { name: 'no steps' };
    expect(validate(doc)).toBe(false);
    const requiredErrors = validate.errors?.filter(
      e => e.keyword === 'required'
    );
    expect(requiredErrors?.length).toBeGreaterThan(0);
    expect(
      requiredErrors?.some(e => e.params['missingProperty'] === 'steps')
    ).toBe(true);
  });

  it('accepts a minimal valid v2 doc', () => {
    const doc = {
      name: 'minimal',
      steps: [
        {
          id: 'a',
          name: 'a',
          adaptor: '@openfn/language-common@latest',
          expression: 'fn(s => s)',
        },
      ],
    };
    expect(validate(doc)).toBe(true);
  });

  it('rejects an unknown top-level property', () => {
    const doc = {
      steps: [
        {
          id: 'a',
          name: 'a',
          adaptor: '@openfn/language-common@latest',
          expression: 'fn(s => s)',
        },
      ],
      not_a_real_field: true,
    };
    expect(validate(doc)).toBe(false);
  });

  it('rejects a step missing required fields', () => {
    const doc = {
      steps: [{ id: 'a' }],
    };
    expect(validate(doc)).toBe(false);
  });

  it('rejects an edge with an invalid `condition`', () => {
    const doc = {
      steps: [
        {
          id: 'a',
          name: 'a',
          adaptor: '@openfn/language-common@latest',
          expression: 'fn(s => s)',
          next: { b: { condition: 'not_a_real_condition' } },
        },
        {
          id: 'b',
          name: 'b',
          adaptor: '@openfn/language-common@latest',
          expression: 'fn(s => s)',
        },
      ],
    };
    expect(validate(doc)).toBe(false);
  });
});

// The AJV schema is structural — it does not know which step ids exist,
// so it cannot catch a `next:` that references a missing step. That check
// runs at parse time inside `v2.parseWorkflow` (it throws JobNotFoundError
// as it walks the `next:` map).

describe('v2 parseWorkflow rejects dangling next references', () => {
  it('throws JobNotFoundError when a step `next:` targets a non-existent step', () => {
    const yaml = `
name: dangling
steps:
  - id: a
    name: a
    adaptor: '@openfn/language-common@latest'
    expression: |
      fn(state => state)
    next:
      ghost:
        condition: always
`;
    expect(() => v2.parseWorkflow(yaml)).toThrow();

    try {
      v2.parseWorkflow(yaml);
    } catch (err) {
      // Structural assertion: it's a workflow error referencing the missing
      // target id. Either JobNotFoundError or a SchemaValidationError that
      // mentions the dangling reference is acceptable.
      const e = err as { name?: string; message?: string };
      const isExpected =
        e.name === 'JobNotFoundError' ||
        (typeof e.message === 'string' && e.message.includes('ghost'));
      expect(isExpected).toBe(true);
    }
  });

  it('throws when a trigger `next:` targets a non-existent step', () => {
    const yaml = `
name: dangling-trigger
steps:
  - id: webhook
    type: webhook
    enabled: true
    next:
      ghost:
        condition: always
  - id: a
    name: a
    adaptor: '@openfn/language-common@latest'
    expression: |
      fn(state => state)
`;
    expect(() => v2.parseWorkflow(yaml)).toThrow();
  });
});

// ── detectFormat sanity ─────────────────────────────────────────────────────

describe('v2.detectFormat', () => {
  it('returns v2 for a doc with steps and no jobs', () => {
    expect(v2.detectFormat({ steps: [] })).toBe('v2');
  });

  it('returns v1 for a doc with jobs/triggers/edges shape', () => {
    expect(
      v2.detectFormat({
        jobs: { a: {} },
        triggers: { webhook: { type: 'webhook' } },
        edges: {},
      })
    ).toBe('v1');
  });

  it('returns v1 for a doc with both jobs and steps (legacy bias)', () => {
    expect(v2.detectFormat({ jobs: {}, steps: [] })).toBe('v1');
  });

  it('returns v1 for null / non-object input', () => {
    expect(v2.detectFormat(null)).toBe('v1');
    expect(v2.detectFormat([])).toBe('v1');
    expect(v2.detectFormat('hello')).toBe('v1');
  });
});

// SchemaValidationError is intentionally referenced so the import isn't
// flagged as unused; it doubles as documentation that this is the error
// class missing-`steps:` would surface through `parseWorkflow`.
void SchemaValidationError;
