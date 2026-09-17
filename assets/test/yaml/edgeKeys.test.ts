/**
 * Edge key disambiguation parity.
 *
 * `test/fixtures/edge_key_disambiguation.json` is generated from
 * `Lightning.ExportUtils.build_yaml_tree/2`. The browser writes the same specs
 * into the same git-synced repos, so if the two disagree the same workflow
 * exports two different ways depending on which side did it.
 *
 * Reachable only since #4577: a job name could not contain `>` before, so
 * `a` + `b->c` and `a->b` + `c` could not both key to `a->b->c`.
 */
import fs from 'node:fs';
import path from 'node:path';

import { describe, expect, test } from 'vitest';

import type { WorkflowState } from '../../js/yaml/types';
import { convertWorkflowStateToSpec } from '../../js/yaml/util';

interface EdgeCase {
  label: string;
  jobs: string[];
  edges: [string, string][];
  keys: string[];
}

const cases = JSON.parse(
  fs.readFileSync(
    path.join(__dirname, '../../../test/fixtures/edge_key_disambiguation.json'),
    'utf8'
  )
) as EdgeCase[];

const specFor = ({ jobs, edges }: EdgeCase) => {
  const jobIds = new Map(jobs.map(name => [name, `job-${jobs.indexOf(name)}`]));

  const state: WorkflowState = {
    id: 'w1',
    name: 'w',
    jobs: jobs.map(name => ({
      id: jobIds.get(name) as string,
      name,
      adaptor: '@openfn/language-common@latest',
      body: 'fn(state => state)',
    })),
    triggers: [],
    edges: edges.map(([source, target], i) => ({
      id: `e${String(i)}`,
      source_job_id: jobIds.get(source) as string,
      target_job_id: jobIds.get(target) as string,
      condition_type: 'on_job_success',
      enabled: true,
    })),
    positions: null,
  } as unknown as WorkflowState;

  return convertWorkflowStateToSpec(state, false);
};

describe('edge keys match the server', () => {
  test('the fixture is not empty', () => {
    expect(cases.length).toBeGreaterThan(3);
  });

  test.each(cases)('$label', edgeCase => {
    const spec = specFor(edgeCase);

    expect(Object.keys(spec.edges).sort()).toEqual([...edgeCase.keys].sort());
  });

  test('no edge is dropped on a collision', () => {
    const collision = cases.find(c => c.label === 'the > collision');
    expect(collision).toBeDefined();

    const spec = specFor(collision as EdgeCase);

    // Two edges in, two out. The browser used to keep the last and the spec
    // came out an edge short, with no error.
    expect(Object.keys(spec.edges)).toHaveLength(2);

    // Both edges still name their own source and target, which is what the
    // CLI reads. The keys collide; the bodies do not.
    const pairs = Object.values(spec.edges)
      .map(e => [e.source_job, e.target_job])
      .sort();

    expect(pairs).toEqual(
      [
        ['a', 'b->c'],
        ['a->b', 'c'],
      ].sort()
    );
  });
});
