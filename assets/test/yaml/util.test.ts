/**
 * YAML Utility Functions Tests
 *
 * Covers:
 *   - `convertWorkflowSpecToState` — v1 spec → state conversion (still the
 *     downstream conversion path for both v1 and v2 imports)
 *   - `parseWorkflowYAML` — format-aware dispatch (v1/v2 detection)
 *   - `parseWorkflowTemplate` — same dispatch on the template-picker read
 *     path; legacy v1 templates still load lenient, v2 templates parse
 *     strictly
 *   - State → v2 YAML round-trip via the public `serializeWorkflow` façade
 *
 * Note: the v1 state → spec serializer was removed in #4718 Phase 4.
 * Outbound YAML emits v2; tests for the public `serializeWorkflow` façade
 * also live in `test/yaml/v2.test.ts`.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { describe, expect, test, vi } from 'vitest';
import YAML from 'yaml';

import {
  convertWorkflowSpecToState,
  parseWorkflowTemplate,
  parseWorkflowYAML,
} from '../../js/yaml/util';
import { serializeWorkflow } from '../../js/yaml/format';
import { parseWorkflow as parseV2 } from '../../js/yaml/v2';
import type { WorkflowSpec, WorkflowState } from '../../js/yaml/types';
import { SchemaValidationError } from '../../js/yaml/workflow-errors';

const FIXTURES_ROOT = resolve(__dirname, '../../../test/fixtures/portability');

// Kitchen-sink fixtures: each format has one comprehensive workflow that
// exercises every supported feature (multi-trigger, cron cursor, webhook
// reply, JS-expression edge with label + disabled, branching, all condition
// types). New features must be added here so regressions surface.
const readKitchenSink = (format: 'v1' | 'v2'): string =>
  readFileSync(`${FIXTURES_ROOT}/${format}/canonical_workflow.yaml`, 'utf-8');

describe('convertWorkflowSpecToState', () => {
  describe('trigger enabled state', () => {
    test('respects explicit enabled: false in spec', () => {
      const spec: WorkflowSpec = {
        name: 'Test Workflow',
        jobs: {
          'job-1': {
            name: 'Job 1',
            adaptor: '@openfn/language-common@latest',
            body: 'fn(state => state)',
          },
        },
        triggers: {
          webhook: {
            type: 'webhook',
            enabled: false,
          },
        },
        edges: {
          'webhook->job-1': {
            source_trigger: 'webhook',
            target_job: 'job-1',
            condition_type: 'always',
          },
        },
      };

      const state = convertWorkflowSpecToState(spec);

      expect(state.triggers).toHaveLength(1);
      expect(state.triggers[0].enabled).toBe(false);
    });

    test('respects explicit enabled: true in spec', () => {
      const spec: WorkflowSpec = {
        name: 'Test Workflow',
        jobs: {
          'job-1': {
            name: 'Job 1',
            adaptor: '@openfn/language-common@latest',
            body: 'fn(state => state)',
          },
        },
        triggers: {
          webhook: {
            type: 'webhook',
            enabled: true,
          },
        },
        edges: {
          'webhook->job-1': {
            source_trigger: 'webhook',
            target_job: 'job-1',
            condition_type: 'always',
          },
        },
      };

      const state = convertWorkflowSpecToState(spec);

      expect(state.triggers).toHaveLength(1);
      expect(state.triggers[0].enabled).toBe(true);
    });

    test('handles multiple triggers with different enabled states', () => {
      const spec: WorkflowSpec = {
        name: 'Test Workflow',
        jobs: {
          'job-1': {
            name: 'Job 1',
            adaptor: '@openfn/language-common@latest',
            body: 'fn(state => state)',
          },
        },
        triggers: {
          webhook: {
            type: 'webhook',
            enabled: false,
          },
          cron: {
            type: 'cron',
            enabled: true,
            cron_expression: '0 0 * * *',
          },
        },
        edges: {
          'webhook->job-1': {
            source_trigger: 'webhook',
            target_job: 'job-1',
            condition_type: 'always',
          },
          'cron->job-1': {
            source_trigger: 'cron',
            target_job: 'job-1',
            condition_type: 'always',
          },
        },
      };

      const state = convertWorkflowSpecToState(spec);

      expect(state.triggers).toHaveLength(2);

      const webhookTrigger = state.triggers.find(t => t.type === 'webhook');
      const cronTrigger = state.triggers.find(t => t.type === 'cron');

      expect(webhookTrigger?.enabled).toBe(false);
      expect(cronTrigger?.enabled).toBe(true);
    });
  });

  describe('round-trip conversion', () => {
    test('preserves trigger enabled state through state → v2 YAML → spec', () => {
      const originalSpec: WorkflowSpec = {
        name: 'Test Workflow',
        jobs: {
          'job-1': {
            name: 'Job 1',
            adaptor: '@openfn/language-common@latest',
            body: 'fn(state => state)',
          },
        },
        triggers: {
          webhook: {
            type: 'webhook',
            enabled: false,
          },
        },
        edges: {
          'webhook->job-1': {
            source_trigger: 'webhook',
            target_job: 'job-1',
            condition_type: 'always',
          },
        },
      };

      const state = convertWorkflowSpecToState(originalSpec);
      const yamlString = serializeWorkflow(state);
      const reparsedSpec = parseV2(YAML.parse(yamlString));

      expect(reparsedSpec.triggers['webhook']?.enabled).toBe(false);
    });

    test('keeps a webhook custom_path on the way in', () => {
      // This used to drop the path silently. Only the parse side is left in
      // the browser: outbound YAML is v2, which carries no custom_path.
      const originalSpec = {
        name: 'Test Workflow',
        jobs: {
          'job-1': {
            name: 'Job 1',
            adaptor: '@openfn/language-common@latest',
            body: 'fn(state => state)',
          },
        },
        triggers: {
          webhook: {
            type: 'webhook',
            enabled: true,
            custom_path: 'et-emr-facility-001',
          },
        },
        edges: {
          'webhook->job-1': {
            source_trigger: 'webhook',
            target_job: 'job-1',
            condition_type: 'always',
          },
        },
      };

      const state = convertWorkflowSpecToState(originalSpec);
      const webhook = state.triggers[0];
      if (webhook?.type !== 'webhook') throw new Error('unreachable');

      expect(webhook.custom_path).toBe('et-emr-facility-001');
    });

    test('leaves custom_path absent when the spec has none', () => {
      // Absent reads as "unchanged" downstream; an explicit null would clear
      // a path the workflow already has.
      const originalSpec = {
        name: 'Test Workflow',
        jobs: {
          'job-1': {
            name: 'Job 1',
            adaptor: '@openfn/language-common@latest',
            body: 'fn(state => state)',
          },
        },
        triggers: { webhook: { type: 'webhook', enabled: true } },
        edges: {
          'webhook->job-1': {
            source_trigger: 'webhook',
            target_job: 'job-1',
            condition_type: 'always',
          },
        },
      };

      const state = convertWorkflowSpecToState(originalSpec);

      expect('custom_path' in state.triggers[0]).toBe(false);
    });
  });
});

// ── Phase 5: format-aware parse dispatch ───────────────────────────────────

describe('parseWorkflowYAML — format detection + dispatch', () => {
  test('parses the v1 canonical workflow into a v1-shaped WorkflowSpec', () => {
    const spec = parseWorkflowYAML(readKitchenSink('v1'));

    expect(spec).toBeDefined();
    expect(typeof spec.name).toBe('string');
    expect(spec.jobs).toBeDefined();
    expect(spec.triggers).toBeDefined();
    expect(spec.edges).toBeDefined();
    expect(Object.keys(spec.jobs).length).toBeGreaterThan(0);
  });

  test('parses the v2 canonical workflow into a v1-shaped WorkflowSpec', () => {
    const spec = parseWorkflowYAML(readKitchenSink('v2'));

    expect(spec).toBeDefined();
    expect(typeof spec.name).toBe('string');
    expect(spec.jobs).toBeDefined();
    expect(spec.triggers).toBeDefined();
    expect(spec.edges).toBeDefined();
    expect(Object.keys(spec.jobs).length).toBeGreaterThan(0);
  });

  test('v1 and v2 canonical workflows parse to structurally equivalent specs', () => {
    const v1Spec = parseWorkflowYAML(readKitchenSink('v1'));
    const v2Spec = parseWorkflowYAML(readKitchenSink('v2'));

    expect(v1Spec.name).toBe(v2Spec.name);
    expect(Object.keys(v1Spec.jobs).sort()).toEqual(
      Object.keys(v2Spec.jobs).sort()
    );
    expect(Object.keys(v1Spec.triggers).sort()).toEqual(
      Object.keys(v2Spec.triggers).sort()
    );

    // Both downstream convert to a WorkflowState the same way.
    const v1State = convertWorkflowSpecToState(v1Spec);
    const v2State = convertWorkflowSpecToState(v2Spec);
    expect(v1State.jobs.length).toBe(v2State.jobs.length);
    expect(v1State.triggers.length).toBe(v2State.triggers.length);
    expect(v1State.edges.length).toBe(v2State.edges.length);
  });

  test('rejects malformed YAML', () => {
    expect(() => parseWorkflowYAML('invalid: [syntax')).toThrow();
  });

  test('rejects an empty document with a workflow validation error', () => {
    // Empty docs become null after YAML.parse — detectFormat biases v1 and
    // emits a console.warn before the v1 schema rejects. Silence the warn so
    // test output stays clean. What matters is that this throws.
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    try {
      expect(() => parseWorkflowYAML('')).toThrow();
    } finally {
      warnSpy.mockRestore();
    }
  });

  test('biases v1 when a doc has both `jobs:` and `steps:` (legacy)', () => {
    // Construct a doc that has both top-level keys. Detect must pick v1 and
    // log a warn. The v1 schema then rejects (jobs is empty / no triggers),
    // but the throw must come from the v1 path — confirmed by the error class.
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const ambiguous = `
name: ambiguous
jobs: {}
steps: []
triggers: {}
edges: {}
`;
    let thrown: unknown;
    try {
      parseWorkflowYAML(ambiguous);
    } catch (err) {
      thrown = err;
    } finally {
      warnSpy.mockRestore();
    }
    expect(thrown).toBeInstanceOf(SchemaValidationError);
  });
});

describe('parseWorkflowTemplate — format detection + dispatch', () => {
  test('parses the v1 canonical workflow template leniently', () => {
    // v1 templates retain the historic lenient parse — `parseWorkflowTemplate`
    // returns the YAML.parse'd object as-is for v1 docs.
    const spec = parseWorkflowTemplate(readKitchenSink('v1'));

    expect(spec).toBeDefined();
    expect((spec as unknown as Record<string, unknown>)['jobs']).toBeDefined();
  });

  test('parses the v2 canonical workflow template into a v1-shaped WorkflowSpec', () => {
    // v2 templates are validated through `v2.parseWorkflow` so the picker
    // gets a v1-shaped `WorkflowSpec` (jobs/triggers/edges maps).
    const spec = parseWorkflowTemplate(readKitchenSink('v2'));

    expect(spec).toBeDefined();
    expect(spec.jobs).toBeDefined();
    expect(spec.triggers).toBeDefined();
    expect(spec.edges).toBeDefined();
    expect(Object.keys(spec.jobs).length).toBeGreaterThan(0);
  });

  test('handles an empty template string without throwing', () => {
    // YAML.parse('') ⇒ null. Lenient v1 path returns null cast.
    expect(() => parseWorkflowTemplate('')).not.toThrow();
  });

  test('surfaces YAML syntax errors', () => {
    expect(() => parseWorkflowTemplate('invalid: [syntax')).toThrow();
  });

  describe('v2 step ids', () => {
    const yamlFor = (jobNames: string[]) =>
      serializeWorkflow({
        id: 'w1',
        name: 'Test Workflow',
        jobs: jobNames.map((name, i) => ({
          id: `j${String(i)}`,
          name,
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        })),
        triggers: [{ id: 't1', type: 'webhook', enabled: true }],
        edges: [],
        positions: null,
      } as unknown as WorkflowState);

    // The server writes the spec and the CLI reads it back, so a step id that
    // differs by one hyphen is a different step. `V2.hyphenate/1` replaces
    // each single space, so two spaces give two hyphens. This used to
    // collapse runs of whitespace and disagreed with the server on exactly
    // that input.
    test('one space, one hyphen, matching the server', () => {
      const yaml = yamlFor(['a  b', 'one two', 'trailing ']);

      expect(yaml).toContain('id: a--b');
      expect(yaml).toContain('id: one-two');
      expect(yaml).toContain("id: 'trailing-'");
    });

    test('leaves names that are not ASCII alone', () => {
      const yaml = yamlFor(['Vérifier l’état', '患者確認']);

      expect(yaml).toContain("id: 'vérifier-l’état'");
      expect(yaml).toContain("id: '患者確認'");
    });

    // A step id of `__proto__` assigned onto a plain object ran the prototype
    // setter instead of adding a key, and the edge to it vanished.
    test('keeps an edge to a step named __proto__', () => {
      const yaml = serializeWorkflow({
        id: 'w1',
        name: 'Test Workflow',
        jobs: [
          {
            id: 'j0',
            name: '__proto__',
            adaptor: '@openfn/language-common@latest',
            body: 'fn(state => state)',
          },
        ],
        triggers: [{ id: 't1', type: 'webhook', enabled: true }],
        edges: [
          {
            id: 'e0',
            source_trigger_id: 't1',
            target_job_id: 'j0',
            condition_type: 'always',
            enabled: true,
          },
        ],
        positions: null,
      } as unknown as WorkflowState);

      expect(yaml).toContain('__proto__');

      const spec = parseV2(YAML.parse(yaml));
      expect(Object.keys(spec.edges)).toHaveLength(1);
    });
  });
});

describe('convertWorkflowSpecToState prototype keys', () => {
  const specWith = (jobNames: string[]): WorkflowSpec => {
    // Null-prototype here too, or the test helper hits the same setter the
    // code under test used to and never builds the case it means to.
    const jobs = Object.create(null) as Record<string, unknown>;
    jobNames.forEach(name => {
      jobs[name] = {
        name,
        adaptor: '@openfn/language-common@latest',
        body: 'fn(state => state)',
      };
    });

    return {
      name: 'Test Workflow',
      jobs,
      triggers: { webhook: { type: 'webhook', enabled: true } },
      edges: {},
    } as unknown as WorkflowSpec;
  };

  test('keeps a job keyed __proto__ on the way in', () => {
    // Assigned onto a plain object this ran the prototype setter and the job
    // never landed, so the state came back one job short.
    const state = convertWorkflowSpecToState(
      specWith(['__proto__', 'a', 'b', 'c', 'd', 'e'])
    );

    expect(state.jobs).toHaveLength(6);
    expect(state.jobs.map(j => j.name).sort()).toEqual([
      '__proto__',
      'a',
      'b',
      'c',
      'd',
      'e',
    ]);
  });

  test('an edge naming a job that is not there still fails', () => {
    // `toString` used to resolve through the prototype, so JobNotFoundError
    // never fired and the edge pointed at nothing.
    const spec = specWith(['real']) as unknown as {
      edges: Record<string, unknown>;
    };
    spec.edges['webhook->toString'] = {
      source_trigger: 'webhook',
      target_job: 'toString',
      condition_type: 'always',
      enabled: true,
    };

    expect(() =>
      convertWorkflowSpecToState(spec as unknown as WorkflowSpec)
    ).toThrow();
  });
});

describe('parseWorkflowYAML duplicate detection', () => {
  const yamlWith = (names: string[]) =>
    [
      'name: Test',
      'jobs:',
      ...names.flatMap((name, i) => [
        `  job-${String(i)}:`,
        `    name: "${name}"`,
        `    adaptor: "@openfn/language-common@latest"`,
        `    body: "fn(state => state)"`,
      ]),
      'triggers:',
      '  webhook:',
      '    type: webhook',
      '    enabled: true',
      'edges: {}',
    ].join('\n');

  // The export side compares hyphenated keys. Comparing raw names here let a
  // spec holding both import cleanly and then throw on the way back out,
  // leaving a workflow that could not be exported.
  test('refuses two names that hyphenate to the same key', () => {
    expect(() => parseWorkflowYAML(yamlWith(['a b', 'a-b']))).toThrow(
      /Duplicate job name/
    );
  });

  test('still accepts names that stay distinct once hyphenated', () => {
    expect(() => parseWorkflowYAML(yamlWith(['a b', 'a c']))).not.toThrow();
  });
});
