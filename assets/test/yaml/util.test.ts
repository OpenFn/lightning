/**
 * YAML Utility Functions Tests
 *
 * Tests for workflow spec <-> state conversion functions
 * with a focus on trigger enabled state defaults.
 */

import { describe, expect, test } from 'vitest';

import {
  convertWorkflowSpecToState,
  convertWorkflowStateToSpec,
  parseWorkflowYAML,
} from '../../js/yaml/util';
import type { WorkflowSpec, WorkflowState } from '../../js/yaml/types';

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
    test('preserves trigger enabled state through conversion cycle', () => {
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
      const convertedSpec = convertWorkflowStateToSpec(state, false);

      expect(convertedSpec.triggers.webhook.enabled).toBe(false);
    });

    test('keeps a webhook custom_path through the round trip', () => {
      // This used to drop the name silently on the way back in.
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
      const convertedSpec = convertWorkflowStateToSpec(state, true);

      expect(convertedSpec.triggers.webhook.custom_path).toBe(
        'et-emr-facility-001'
      );
    });

    test('strips custom_path when ids are stripped, as for a template', () => {
      // A path is per-project identity, so a template must not carry one.
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
      const convertedSpec = convertWorkflowStateToSpec(state, false);

      expect('custom_path' in convertedSpec.triggers.webhook).toBe(false);
    });

    test('does not export a path the server would reject on import', () => {
      // A pre-migration path would fail the import it is deployed into.
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
          webhook: { type: 'webhook', enabled: true, custom_path: 'Order.v1' },
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
      const convertedSpec = convertWorkflowStateToSpec(state, true);

      expect('custom_path' in convertedSpec.triggers.webhook).toBe(false);
    });

    test('omits custom_path when there is none', () => {
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
      const convertedSpec = convertWorkflowStateToSpec(state, true);

      expect('custom_path' in convertedSpec.triggers.webhook).toBe(false);
    });
  });
});

describe('convertWorkflowStateToSpec', () => {
  test('includes enabled field in trigger spec', () => {
    const state: WorkflowState = {
      id: 'w1',
      name: 'Test Workflow',
      jobs: [
        {
          id: 'j1',
          name: 'Job 1',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
      ],
      triggers: [
        {
          id: 't1',
          type: 'webhook',
          enabled: false,
        },
      ],
      edges: [
        {
          id: 'e1',
          source_trigger_id: 't1',
          target_job_id: 'j1',
          condition_type: 'always',
        },
      ],
      positions: null,
    };

    const spec = convertWorkflowStateToSpec(state, false);

    expect(spec.triggers.webhook.enabled).toBe(false);
  });

  describe('job keys', () => {
    const specFor = (jobNames: string[]) => {
      const state: WorkflowState = {
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
      };

      return convertWorkflowStateToSpec(state, false);
    };

    // The server writes the canonical spec and the CLI reads it back, so a
    // key that differs by one hyphen is a different job. ExportUtils.hyphenate/1
    // replaces each single space, so two spaces give two hyphens. This used to
    // collapse runs of whitespace and disagreed with the server on exactly
    // that input.
    test('one space, one hyphen, matching the server', () => {
      const spec = specFor(['a  b', 'one two', 'trailing ']);

      expect(Object.keys(spec.jobs).sort()).toEqual(
        ['a--b', 'one-two', 'trailing-'].sort()
      );
    });

    // The server refuses this pair rather than exporting a spec with one job
    // missing; the browser used to keep the last silently.
    test('refuses two job names that hyphenate to the same key', () => {
      expect(() => specFor(['a b', 'a-b'])).toThrow(/Duplicate job name/);
    });

    // A job named `__proto__` assigned onto a plain object ran the prototype
    // setter instead of adding a key, so the job silently vanished from the
    // spec and the collision check never saw it.
    test('keeps a job named __proto__ in the spec', () => {
      const spec = specFor(['__proto__', 'ordinary']);

      expect(Object.keys(spec.jobs).sort()).toEqual(['__proto__', 'ordinary']);
      expect(spec.jobs['__proto__']?.name).toBe('__proto__');
    });

    test('still refuses a duplicate __proto__ rather than dropping one', () => {
      expect(() => specFor(['__proto__', '__proto__'])).toThrow(
        /Duplicate job name/
      );
    });

    test('keeps jobs named constructor and toString', () => {
      const spec = specFor(['constructor', 'toString', 'hasOwnProperty']);

      expect(Object.keys(spec.jobs).sort()).toEqual([
        'constructor',
        'hasOwnProperty',
        'toString',
      ]);
    });

    test('leaves names that are not ASCII alone', () => {
      const spec = specFor(['Vérifier l’état', '患者確認', 'step 🎉']);

      expect(Object.keys(spec.jobs).sort()).toEqual(
        ['Vérifier-l’état', '患者確認', 'step-🎉'].sort()
      );
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
