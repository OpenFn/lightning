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
});
