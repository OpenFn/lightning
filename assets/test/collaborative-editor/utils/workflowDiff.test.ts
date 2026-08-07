/**
 * workflowDiff - Tests for the AI chat workflow diff derivation
 *
 * Covers per-step body diffs (hunks + line counts), step add/remove/rename,
 * edge and trigger structural rows, the before=null all-adds case, and the
 * null returns for identical or malformed YAML.
 */

import { describe, it, expect, vi, afterEach } from 'vitest';

import { deriveWorkflowChanges } from '../../../js/collaborative-editor/utils/workflowDiff';

interface YamlJob {
  key: string;
  id: string;
  name: string;
  adaptor?: string;
  body: string;
}

interface YamlTrigger {
  id: string;
  type?: 'webhook' | 'cron';
  enabled?: boolean;
  cron_expression?: string;
}

interface YamlEdge {
  key: string;
  id: string;
  source_trigger?: string;
  source_job?: string;
  target_job: string;
  condition_type?: string;
  enabled?: boolean;
}

/** Builds a schema-valid workflow YAML string from compact descriptions */
const buildYaml = ({
  jobs = [],
  triggers = [],
  edges = [],
}: {
  jobs?: YamlJob[];
  triggers?: YamlTrigger[];
  edges?: YamlEdge[];
}): string => {
  const lines: string[] = ['id: wf-1', 'name: Test Workflow'];

  lines.push(jobs.length ? 'jobs:' : 'jobs: {}');
  for (const job of jobs) {
    lines.push(
      `  ${job.key}:`,
      `    id: ${job.id}`,
      `    name: ${job.name}`,
      `    adaptor: '${job.adaptor ?? '@openfn/language-common@latest'}'`,
      '    body: |'
    );
    for (const bodyLine of job.body.split('\n')) {
      lines.push(`      ${bodyLine}`);
    }
  }

  lines.push(triggers.length ? 'triggers:' : 'triggers: {}');
  for (const trigger of triggers) {
    const type = trigger.type ?? 'webhook';
    lines.push(
      `  ${type}:`,
      `    id: ${trigger.id}`,
      `    type: ${type}`,
      `    enabled: ${trigger.enabled ?? true}`
    );
    if (trigger.cron_expression) {
      lines.push(`    cron_expression: '${trigger.cron_expression}'`);
    }
  }

  lines.push(edges.length ? 'edges:' : 'edges: {}');
  for (const edge of edges) {
    lines.push(`  ${edge.key}:`, `    id: ${edge.id}`);
    if (edge.source_trigger) {
      lines.push(`    source_trigger: ${edge.source_trigger}`);
    }
    if (edge.source_job) lines.push(`    source_job: ${edge.source_job}`);
    lines.push(
      `    target_job: ${edge.target_job}`,
      `    condition_type: ${edge.condition_type ?? 'always'}`,
      `    enabled: ${edge.enabled ?? true}`
    );
  }

  return lines.join('\n') + '\n';
};

const webhookTrigger: YamlTrigger = { id: 'trigger-1', type: 'webhook' };

const transformJob = (body: string, name = 'Transform data'): YamlJob => ({
  key: 'transform-data',
  id: 'job-1',
  name,
  body,
});

const webhookToTransformEdge: YamlEdge = {
  key: 'webhook->transform-data',
  id: 'edge-1',
  source_trigger: 'webhook',
  target_job: 'transform-data',
};

const baseWorkflow = (body: string) =>
  buildYaml({
    jobs: [transformJob(body)],
    triggers: [webhookTrigger],
    edges: [webhookToTransformEdge],
  });

afterEach(() => {
  vi.restoreAllMocks();
});

describe('deriveWorkflowChanges', () => {
  describe('step body updates', () => {
    it('produces an update step with correct hunks and line counts', () => {
      const before = baseWorkflow(
        'fn(state => state);\nconst a = 1;\nconst b = 2;\nconst c = 3;\nconst d = 4;'
      );
      const after = baseWorkflow(
        'fn(state => state.data);\nconst a = 1;\nconst b = 2;\nconst c = 3;\nconst d = 4;\nconst e = 5;'
      );

      const changes = deriveWorkflowChanges(before, after);

      expect(changes).not.toBeNull();
      expect(changes!.structure).toEqual([]);
      expect(changes!.steps).toHaveLength(1);

      const step = changes!.steps[0]!;
      expect(step.type).toBe('update');
      expect(step.name).toBe('Transform data');
      expect(step.addedLines).toBe(2);
      expect(step.removedLines).toBe(1);

      expect(step.hunks).toHaveLength(1);
      const hunk = step.hunks[0]!;
      expect(hunk.oldStart).toBe(1);
      expect(hunk.newStart).toBe(1);
      expect(hunk.lines).toContain('-fn(state => state);');
      expect(hunk.lines).toContain('+fn(state => state.data);');
      expect(hunk.lines).toContain('+const e = 5;');
      // Context lines carry a leading space
      expect(hunk.lines).toContain(' const a = 1;');
    });

    it('splits distant edits into multiple hunks with correct starts', () => {
      const body = (mid: string, last: string) =>
        [
          mid,
          ...Array.from({ length: 10 }, (_, i) => `const x${i} = ${i};`),
          last,
        ].join('\n');
      const before = baseWorkflow(body('first();', 'last();'));
      const after = baseWorkflow(body('firstChanged();', 'lastChanged();'));

      const step = deriveWorkflowChanges(before, after)!.steps[0]!;
      expect(step.hunks).toHaveLength(2);
      expect(step.hunks[0]!.oldStart).toBe(1);
      expect(step.hunks[1]!.oldStart).toBeGreaterThan(1);
      expect(step.addedLines).toBe(2);
      expect(step.removedLines).toBe(2);
    });
  });

  describe('step add / remove / rename', () => {
    it('reports a job only in after as an add with its body line count', () => {
      const before = baseWorkflow('fn(state => state);');
      const after = buildYaml({
        jobs: [
          transformJob('fn(state => state);'),
          {
            key: 'send-to-gmail',
            id: 'job-2',
            name: 'Send to Gmail',
            body: 'sendEmail();\nlog();',
          },
        ],
        triggers: [webhookTrigger],
        edges: [webhookToTransformEdge],
      });

      const changes = deriveWorkflowChanges(before, after)!;
      expect(changes.steps).toHaveLength(1);
      const step = changes.steps[0]!;
      expect(step.type).toBe('add');
      expect(step.name).toBe('Send to Gmail');
      expect(step.addedLines).toBe(2);
      expect(step.removedLines).toBe(0);
      expect(step.hunks[0]!.lines).toEqual(['+sendEmail();', '+log();']);
    });

    it('reports a job only in before as a remove', () => {
      const before = buildYaml({
        jobs: [
          transformJob('fn(state => state);'),
          {
            key: 'old-step',
            id: 'job-2',
            name: 'Old step',
            body: 'cleanup();',
          },
        ],
        triggers: [webhookTrigger],
        edges: [webhookToTransformEdge],
      });
      const after = baseWorkflow('fn(state => state);');

      const changes = deriveWorkflowChanges(before, after)!;
      expect(changes.steps).toHaveLength(1);
      const step = changes.steps[0]!;
      expect(step.type).toBe('remove');
      expect(step.name).toBe('Old step');
      expect(step.removedLines).toBe(1);
      expect(step.hunks[0]!.lines).toEqual(['-cleanup();']);
    });

    it('reports a same-id name change as a rename row, with the body diff under the new name', () => {
      const before = baseWorkflow('fn(state => state);');
      const after = buildYaml({
        jobs: [
          {
            key: 'clean-data',
            id: 'job-1',
            name: 'Clean data',
            body: 'fn(state => cleaned(state));',
          },
        ],
        triggers: [webhookTrigger],
        edges: [
          {
            ...webhookToTransformEdge,
            key: 'webhook->clean-data',
            target_job: 'clean-data',
          },
        ],
      });

      const changes = deriveWorkflowChanges(before, after)!;
      expect(changes.structure).toEqual([
        {
          kind: 'rename',
          change: 'modify',
          description: 'Transform data → Clean data',
        },
      ]);
      expect(changes.steps).toHaveLength(1);
      expect(changes.steps[0]!.type).toBe('update');
      expect(changes.steps[0]!.name).toBe('Clean data');
    });

    it('reports a pure rename (unchanged body) with no step block', () => {
      const before = baseWorkflow('fn(state => state);');
      const after = buildYaml({
        jobs: [
          {
            key: 'clean-data',
            id: 'job-1',
            name: 'Clean data',
            body: 'fn(state => state);',
          },
        ],
        triggers: [webhookTrigger],
        edges: [
          {
            ...webhookToTransformEdge,
            key: 'webhook->clean-data',
            target_job: 'clean-data',
          },
        ],
      });

      const changes = deriveWorkflowChanges(before, after)!;
      expect(changes.steps).toEqual([]);
      expect(changes.structure).toHaveLength(1);
      expect(changes.structure[0]!.kind).toBe('rename');
    });
  });

  describe('edges', () => {
    it('reports added and removed edges using source/target names', () => {
      const jobs = [
        transformJob('fn(state => state);'),
        {
          key: 'send-to-gmail',
          id: 'job-2',
          name: 'Send to Gmail',
          body: 'sendEmail();',
        },
      ];
      const before = buildYaml({
        jobs,
        triggers: [webhookTrigger],
        edges: [
          webhookToTransformEdge,
          {
            key: 'webhook->send-to-gmail',
            id: 'edge-2',
            source_trigger: 'webhook',
            target_job: 'send-to-gmail',
          },
        ],
      });
      const after = buildYaml({
        jobs,
        triggers: [webhookTrigger],
        edges: [
          webhookToTransformEdge,
          {
            key: 'transform-data->send-to-gmail',
            id: 'edge-3',
            source_job: 'transform-data',
            target_job: 'send-to-gmail',
          },
        ],
      });

      const changes = deriveWorkflowChanges(before, after)!;
      expect(changes.steps).toEqual([]);

      const added = changes.structure.find(
        row => row.kind === 'edge' && row.change === 'add'
      );
      const removed = changes.structure.find(
        row => row.kind === 'edge' && row.change === 'remove'
      );
      expect(added?.description).toBe('Transform data → Send to Gmail');
      expect(removed?.description).toBe('webhook → Send to Gmail');
    });

    it('reports a condition change as a modified edge row', () => {
      const before = baseWorkflow('fn(state => state);');
      const after = buildYaml({
        jobs: [transformJob('fn(state => state);')],
        triggers: [webhookTrigger],
        edges: [
          { ...webhookToTransformEdge, condition_type: 'on_job_success' },
        ],
      });

      const changes = deriveWorkflowChanges(before, after)!;
      expect(changes.structure).toHaveLength(1);
      const row = changes.structure[0]!;
      expect(row.kind).toBe('edge');
      expect(row.change).toBe('modify');
      expect(row.description).toBe('webhook → Transform data');
      expect(row.detail).toContain('condition: always → on_job_success');
    });
  });

  describe('triggers', () => {
    it('reports enabled and type changes as trigger rows', () => {
      const before = baseWorkflow('fn(state => state);');
      const disabledAfter = buildYaml({
        jobs: [transformJob('fn(state => state);')],
        triggers: [{ ...webhookTrigger, enabled: false }],
        edges: [webhookToTransformEdge],
      });

      const enabledChange = deriveWorkflowChanges(before, disabledAfter)!;
      expect(enabledChange.structure).toEqual([
        {
          kind: 'trigger',
          change: 'modify',
          description: 'webhook trigger',
          detail: 'disabled',
        },
      ]);

      const cronAfter = buildYaml({
        jobs: [transformJob('fn(state => state);')],
        triggers: [
          {
            id: 'trigger-1',
            type: 'cron',
            cron_expression: '0 * * * *',
          },
        ],
        edges: [
          {
            ...webhookToTransformEdge,
            key: 'cron->transform-data',
            source_trigger: 'cron',
          },
        ],
      });

      const typeChange = deriveWorkflowChanges(before, cronAfter)!;
      const triggerRow = typeChange.structure.find(
        row => row.kind === 'trigger'
      );
      expect(triggerRow?.change).toBe('modify');
      expect(triggerRow?.detail).toContain('type: webhook → cron');
    });
  });

  describe('before missing or empty', () => {
    it('treats null before as an empty workflow: everything is an add', () => {
      const after = baseWorkflow('fn(state => state);\nlog(state);');

      const changes = deriveWorkflowChanges(null, after)!;
      expect(changes.steps).toHaveLength(1);
      expect(changes.steps[0]!.type).toBe('add');
      expect(changes.steps[0]!.addedLines).toBe(2);

      const structureChanges = changes.structure.map(row => row.change);
      expect(structureChanges).toEqual(['add', 'add']); // trigger + edge
    });

    it('treats whitespace-only before the same as null', () => {
      const after = baseWorkflow('fn(state => state);');
      const changes = deriveWorkflowChanges('   \n', after)!;
      expect(changes.steps[0]!.type).toBe('add');
    });
  });

  describe('null returns', () => {
    it('returns null when the YAMLs are identical', () => {
      const yaml = baseWorkflow('fn(state => state);');
      expect(deriveWorkflowChanges(yaml, yaml)).toBeNull();
    });

    it('returns null and warns when the after YAML is malformed', () => {
      const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
      expect(deriveWorkflowChanges(null, 'jobs: [not: valid yaml')).toBeNull();
      expect(warnSpy).toHaveBeenCalledTimes(1);
    });

    it('returns null and warns when the before YAML is malformed', () => {
      const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
      expect(
        deriveWorkflowChanges(
          'triggers: {{',
          baseWorkflow('fn(state => state);')
        )
      ).toBeNull();
      expect(warnSpy).toHaveBeenCalledTimes(1);
    });
  });
});
