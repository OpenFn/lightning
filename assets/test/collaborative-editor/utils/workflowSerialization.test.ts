import { describe, expect, test } from 'vitest';

import { withDisabledTriggers } from '../../../js/collaborative-editor/utils/workflowSerialization';
import type { WorkflowState } from '../../../js/yaml/types';

describe('withDisabledTriggers', () => {
  test('disables all triggers in workflow state', () => {
    const state: WorkflowState = {
      id: 'w1',
      name: 'Test Workflow',
      triggers: [
        { id: 't1', type: 'webhook', enabled: true },
        { id: 't2', type: 'cron', enabled: true, cron_expression: '0 0 * * *' },
      ],
      jobs: [],
      edges: [],
      positions: null,
    };

    const result = withDisabledTriggers(state);

    expect(result.triggers).toHaveLength(2);
    expect(result.triggers[0].enabled).toBe(false);
    expect(result.triggers[1].enabled).toBe(false);
  });

  test('preserves other trigger properties', () => {
    const state: WorkflowState = {
      id: 'w1',
      name: 'Test',
      triggers: [
        { id: 't1', type: 'cron', enabled: true, cron_expression: '0 0 * * *' },
      ],
      jobs: [],
      edges: [],
      positions: null,
    };

    const result = withDisabledTriggers(state);

    expect(result.triggers[0]).toEqual({
      id: 't1',
      type: 'cron',
      enabled: false,
      cron_expression: '0 0 * * *',
    });
  });

  test('preserves other state properties', () => {
    const state: WorkflowState = {
      id: 'w1',
      name: 'My Workflow',
      triggers: [{ id: 't1', type: 'webhook', enabled: true }],
      jobs: [
        {
          id: 'j1',
          name: 'Job 1',
          adaptor: '@openfn/language-common@latest',
          body: '',
        },
      ],
      edges: [
        {
          id: 'e1',
          source_trigger_id: 't1',
          target_job_id: 'j1',
          condition_type: 'always',
          enabled: true,
        },
      ],
      positions: { t1: { x: 0, y: 0 }, j1: { x: 100, y: 100 } },
    };

    const result = withDisabledTriggers(state);

    expect(result.id).toBe('w1');
    expect(result.name).toBe('My Workflow');
    expect(result.jobs).toEqual(state.jobs);
    expect(result.edges).toEqual(state.edges);
    expect(result.positions).toEqual(state.positions);
  });

  test('handles already disabled triggers', () => {
    const state: WorkflowState = {
      id: 'w1',
      name: 'Test',
      triggers: [
        { id: 't1', type: 'webhook', enabled: false },
        { id: 't2', type: 'cron', enabled: true, cron_expression: '0 0 * * *' },
      ],
      jobs: [],
      edges: [],
      positions: null,
    };

    const result = withDisabledTriggers(state);

    expect(result.triggers[0].enabled).toBe(false);
    expect(result.triggers[1].enabled).toBe(false);
  });

  test('handles empty triggers array', () => {
    const state: WorkflowState = {
      id: 'w1',
      name: 'Test',
      triggers: [],
      jobs: [],
      edges: [],
      positions: null,
    };

    const result = withDisabledTriggers(state);

    expect(result.triggers).toEqual([]);
  });

  test('returns new object (immutable)', () => {
    const state: WorkflowState = {
      id: 'w1',
      name: 'Test',
      triggers: [{ id: 't1', type: 'webhook', enabled: true }],
      jobs: [],
      edges: [],
      positions: null,
    };

    const result = withDisabledTriggers(state);

    expect(result).not.toBe(state);
    expect(result.triggers).not.toBe(state.triggers);
    expect(result.triggers[0]).not.toBe(state.triggers[0]);
    // Original unchanged
    expect(state.triggers[0].enabled).toBe(true);
  });
});
