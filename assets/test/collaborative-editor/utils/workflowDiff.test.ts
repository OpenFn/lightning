/**
 * workflowDiff - Tests for the AI chat workflow diff derivation
 *
 * Covers per-step body diffs (hunks + line counts), step add/remove/rename,
 * edge and trigger structural rows, the before=null all-adds case, and the
 * null returns for identical or malformed YAML.
 */

import { describe, it, expect, vi, afterEach } from 'vitest';

import {
  assignStepDiffsToStatuses,
  deriveSnapshotChanges,
  deriveWorkflowChanges,
} from '../../../js/collaborative-editor/utils/workflowDiff';
import type { StepChange } from '../../../js/collaborative-editor/utils/workflowDiff';

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

describe('assignStepDiffsToStatuses', () => {
  const step = (name: string): StepChange => ({
    type: 'update',
    name,
    addedLines: 1,
    removedLines: 1,
    hunks: [],
  });

  const status = (steps: string[]) => ({
    type: 'status',
    steps: steps.map(name => ({ key: name.toLowerCase(), name })),
  });

  it('assigns steps to the status that reports touching them', () => {
    const steps = [step('Transform data'), step('Send to Gmail')];
    const segments = [
      { type: 'text' },
      status(['Transform data', 'Send to Gmail']),
    ];

    const { byStatusIndex, unmatched } = assignStepDiffsToStatuses(
      steps,
      segments
    );

    expect(byStatusIndex.get(1)).toEqual(steps);
    expect(unmatched).toEqual([]);
  });

  it('ignores the status prose entirely', () => {
    const steps = [step('Transform data')];
    // The sentence names the step; the data says this action touched
    // nothing. The data wins — that is the whole point of the change.
    const segments = [
      { type: 'status', content: 'Wrote code for "Transform data"' },
    ];

    const { byStatusIndex, unmatched } = assignStepDiffsToStatuses(
      steps,
      segments
    );

    expect(byStatusIndex.size).toBe(0);
    expect(unmatched).toEqual(steps);
  });

  it('assigns a step edited twice to the last status that touched it', () => {
    const steps = [step('Transform data')];
    const segments = [status(['Transform data']), status(['Transform data'])];

    const { byStatusIndex, unmatched } = assignStepDiffsToStatuses(
      steps,
      segments
    );

    // Reload has one cumulative diff per step, and it only reaches the body
    // it shows at the last edit, so an earlier status would misdescribe it.
    expect([...byStatusIndex.keys()]).toEqual([1]);
    expect(unmatched).toEqual([]);
  });

  it('matches a status that reported only the key', () => {
    const steps = [step('Transform data')];
    const segments = [{ type: 'status', steps: [{ key: 'transform-data' }] }];

    const { byStatusIndex } = assignStepDiffsToStatuses(steps, segments);

    // `key` is the required field on the wire; the YAML writer derives it
    // from the name, so the same transform recovers it here.
    expect(byStatusIndex.get(0)).toEqual(steps);
  });

  it('leaves steps no status claimed unmatched', () => {
    const steps = [step('Transform data'), step('Send to Gmail')];
    const segments = [status(['Transform data'])];

    const { byStatusIndex, unmatched } = assignStepDiffsToStatuses(
      steps,
      segments
    );

    expect(byStatusIndex.get(0)).toEqual([steps[0]]);
    expect(unmatched).toEqual([steps[1]]);
  });

  it('matches names case-insensitively, since the two sides are recorded apart', () => {
    const steps = [step('Transform data')];
    const segments = [status(['TRANSFORM DATA'])];

    const { byStatusIndex } = assignStepDiffsToStatuses(steps, segments);

    expect(byStatusIndex.get(0)).toEqual(steps);
  });

  it('claims nothing for a reply from an Apollo that reports no steps', () => {
    const steps = [step('Transform data')];
    const segments = [{ type: 'status', content: 'Edited workflow structure' }];

    const { byStatusIndex, unmatched } = assignStepDiffsToStatuses(
      steps,
      segments
    );

    // Blocks fall to the end of the message rather than being misattributed.
    expect(byStatusIndex.size).toBe(0);
    expect(unmatched).toEqual(steps);
  });
});

describe('YAML re-serialization', () => {
  /** Same body, written as an inline scalar instead of a block scalar */
  const inlineBodyWorkflow = (body: string) =>
    [
      'id: wf-1',
      'name: Test Workflow',
      'jobs:',
      '  transform-data:',
      '    id: job-1',
      '    name: Transform data',
      "    adaptor: '@openfn/language-common@latest'",
      `    body: ${body}`,
      'triggers:',
      '  webhook:',
      '    id: trigger-1',
      '    type: webhook',
      '    enabled: true',
      'edges:',
      '  webhook->transform-data:',
      '    id: edge-1',
      '    source_trigger: webhook',
      '    target_job: transform-data',
      '    condition_type: always',
      '    enabled: true',
    ].join('\n') + '\n';

  it('reports no change when only the scalar style differs', () => {
    // Apollo rewrites the whole document on every mutation, so a `body: |`
    // block becomes inline and the parsed strings differ by a trailing
    // newline. That is not an edit and must not render a blank block.
    const before = baseWorkflow('fn(state => state);');
    const after = inlineBodyWorkflow('fn(state => state);');

    expect(deriveWorkflowChanges(before, after)).toBeNull();
  });

  it('still reports a real edit made in the re-serialized style', () => {
    const before = baseWorkflow('fn(state => state);');
    const after = inlineBodyWorkflow('fn(state => state.data);');

    const changes = deriveWorkflowChanges(before, after);

    expect(changes?.steps).toHaveLength(1);
    expect(changes?.steps[0]).toMatchObject({
      type: 'update',
      addedLines: 1,
      removedLines: 1,
    });
  });
});

describe('edges without preserved ids', () => {
  /** Same workflow twice, with no `id:` anywhere */
  const idlessYaml = (body: string) =>
    [
      'name: Test Workflow',
      'jobs:',
      '  transform-data:',
      '    name: Transform data',
      "    adaptor: '@openfn/language-common@latest'",
      `    body: ${body}`,
      'triggers:',
      '  webhook:',
      '    type: webhook',
      '    enabled: true',
      'edges:',
      '  webhook->transform-data:',
      '    source_trigger: webhook',
      '    target_job: transform-data',
      '    condition_type: always',
      '    enabled: true',
    ].join('\n') + '\n';

  it('does not report an unchanged edge as rewired', () => {
    // Parsing id-less YAML invents a fresh UUID per entity, so the two sides
    // never agree on ids. Reporting that as a rewire put a bogus Structure
    // row under every status of every reply.
    const changes = deriveWorkflowChanges(
      idlessYaml('fn(s => s);'),
      idlessYaml('fn(s => s.data);')
    );

    expect(changes?.steps).toHaveLength(1);
    expect(changes?.structure).toEqual([]);
  });

  it('reports a rename as a rename, not a remove plus an add', () => {
    const named = (name: string, body: string) =>
      [
        'name: Test Workflow',
        'jobs:',
        '  step-one:',
        `    name: ${name}`,
        "    adaptor: '@openfn/language-common@latest'",
        `    body: ${body}`,
        'triggers:',
        '  webhook:',
        '    type: webhook',
        '    enabled: true',
        'edges:',
        '  webhook->step-one:',
        '    source_trigger: webhook',
        `    target_job: step-one`,
        '    condition_type: always',
        '    enabled: true',
      ].join('\n') + '\n';

    const changes = deriveWorkflowChanges(
      named('Fetch data', 'fn(s => s);'),
      named('Fetch records', 'fn(s => s.body);')
    );

    // Without id or name to pair on, this used to read as two whole-body
    // blocks plus edge rows for wiring that never moved.
    expect(changes?.steps.map(step => step.type)).toEqual(['update']);
    expect(changes?.structure).toContainEqual(
      expect.objectContaining({
        kind: 'rename',
        description: 'Fetch data → Fetch records',
      })
    );
    expect(changes?.structure.filter(row => row.kind === 'edge')).toEqual([]);
  });

  it('still reports an edge whose endpoints actually moved', () => {
    const before = buildYaml({
      jobs: [
        transformJob('fn(s => s);'),
        {
          key: 'send-mail',
          id: 'job-2',
          name: 'Send mail',
          body: 'fn(s => s);',
        },
      ],
      triggers: [webhookTrigger],
      edges: [webhookToTransformEdge],
    });
    const after = buildYaml({
      jobs: [
        transformJob('fn(s => s);'),
        {
          key: 'send-mail',
          id: 'job-2',
          name: 'Send mail',
          body: 'fn(s => s);',
        },
      ],
      triggers: [webhookTrigger],
      edges: [
        {
          key: 'webhook->transform-data',
          id: 'edge-1',
          source_trigger: 'webhook',
          target_job: 'send-mail',
        },
      ],
    });

    const changes = deriveWorkflowChanges(before, after);

    expect(changes?.structure).toContainEqual(
      expect.objectContaining({ kind: 'edge', change: 'modify' })
    );
  });
});

describe('deriveSnapshotChanges', () => {
  const snapshot = (yaml: string, segmentIndex: number) => ({
    yaml,
    segmentIndex,
  });

  it('diffs each snapshot against its predecessor, not against the baseline', () => {
    const baseline = baseWorkflow('fn(s => s);');
    const first = baseWorkflow('fn(s => s);\nconsole.log(1);');
    const second = baseWorkflow(
      'fn(s => s);\nconsole.log(1);\nconsole.log(2);'
    );

    const result = deriveSnapshotChanges(baseline, [
      snapshot(first, 0),
      snapshot(second, 1),
    ]);

    expect(result).toHaveLength(2);
    // Each step reports only the line its own action added, which is the
    // whole point: a cumulative diff would report 1 then 2.
    expect(result[0]!.changes.steps[0]!.addedLines).toBe(1);
    expect(result[1]!.changes.steps[0]!.addedLines).toBe(1);
  });

  it('pins each change set to the segment index its snapshot carried', () => {
    const baseline = baseWorkflow('fn(s => s);');
    const edited = baseWorkflow('fn(s => s);\nconsole.log(1);');

    const result = deriveSnapshotChanges(baseline, [snapshot(edited, 3)]);

    expect(result[0]!.segmentIndex).toBe(3);
  });

  it('treats a missing baseline as an empty workflow so the first action reads as adds', () => {
    const first = baseWorkflow('fn(s => s);');

    const result = deriveSnapshotChanges(null, [snapshot(first, 0)]);

    expect(result[0]!.changes.steps[0]!.type).toBe('add');
  });

  it('drops snapshots that changed nothing rather than leaving an empty block', () => {
    const baseline = baseWorkflow('fn(s => s);');
    const unchanged = baseWorkflow('fn(s => s);');
    const edited = baseWorkflow('fn(s => s);\nconsole.log(1);');

    const result = deriveSnapshotChanges(baseline, [
      snapshot(unchanged, 0),
      snapshot(edited, 1),
    ]);

    expect(result).toHaveLength(1);
    expect(result[0]!.segmentIndex).toBe(1);
  });

  it('reports structural changes on the snapshot that introduced them', () => {
    const baseline = buildYaml({
      jobs: [transformJob('fn(s => s);')],
      triggers: [webhookTrigger],
      edges: [webhookToTransformEdge],
    });
    const withSecondStep = buildYaml({
      jobs: [
        transformJob('fn(s => s);'),
        {
          key: 'send-mail',
          id: 'job-2',
          name: 'Send mail',
          body: 'fn(s => s);',
        },
      ],
      triggers: [webhookTrigger],
      edges: [
        webhookToTransformEdge,
        {
          key: 'transform-data->send-mail',
          id: 'edge-2',
          source_job: 'transform-data',
          target_job: 'send-mail',
        },
      ],
    });

    const result = deriveSnapshotChanges(baseline, [
      snapshot(withSecondStep, 0),
    ]);

    expect(result[0]!.changes.steps.map(step => step.name)).toEqual([
      'Send mail',
    ]);
    expect(result[0]!.changes.structure).toContainEqual(
      expect.objectContaining({ kind: 'edge', change: 'add' })
    );
  });

  it('returns nothing when there are no snapshots', () => {
    expect(deriveSnapshotChanges(baseWorkflow('fn(s => s);'), [])).toEqual([]);
  });

  it('skips an unparseable snapshot without losing the ones around it', () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const baseline = baseWorkflow('fn(s => s);');
    const edited = baseWorkflow('fn(s => s);\nconsole.log(1);');

    const result = deriveSnapshotChanges(baseline, [
      snapshot('{{ not yaml', 0),
      snapshot(edited, 1),
    ]);

    expect(result).toHaveLength(1);
    expect(result[0]!.segmentIndex).toBe(1);
  });
});
