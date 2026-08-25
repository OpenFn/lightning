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
import type { WorkflowSpec } from '../../js/yaml/types';
import { SchemaValidationError } from '../../js/yaml/workflow-errors';

const FIXTURES_ROOT = resolve(__dirname, '../../../test/fixtures/portability');

// Kitchen-sink fixtures: each format has one comprehensive workflow that
// exercises every supported feature (multi-trigger, kafka config, cron
// cursor, webhook reply, JS-expression edge with label + disabled,
// branching, all condition types). New features must be added here so
// regressions surface.
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
});
