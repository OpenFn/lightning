/**
 * from-workflow Utility Tests
 *
 * Tests that the from-workflow utility correctly converts workflow data
 * to ReactFlow model, with special focus on trigger data transformation.
 */

import { describe, expect, test } from 'vitest';

import fromWorkflow from '../../../js/workflow-diagram/util/from-workflow';
import type { Lightning, Positions } from '../../../js/workflow-diagram/types';

describe('from-workflow - Trigger Data Transformation', () => {
  test('includes cron_expression in trigger node data for cron triggers', () => {
    const workflow: Lightning.Workflow = {
      id: 'workflow-1',
      jobs: [],
      triggers: [
        {
          id: 'trigger-1',
          name: 'Daily Cron',
          type: 'cron',
          enabled: true,
          cron_expression: '0 0 * * *',
          workflow_id: 'workflow-1',
        },
      ],
      edges: [],
      disabled: false,
      positions: {},
    };

    const positions: Positions = {
      'trigger-1': { x: 100, y: 100 },
    };

    const model = fromWorkflow(
      workflow,
      positions,
      { nodes: [], edges: [] },
      { steps: [] },
      null
    );

    expect(model.nodes).toHaveLength(1);
    const triggerNode = model.nodes[0];

    // Check that trigger data includes cron_expression
    expect(triggerNode.data.trigger).toBeDefined();
    expect(triggerNode.data.trigger.type).toBe('cron');
    expect(triggerNode.data.trigger.cron_expression).toBe('0 0 * * *');
  });

  test('includes has_auth_method in trigger node data for webhook triggers', () => {
    const workflow: Lightning.Workflow = {
      id: 'workflow-1',
      jobs: [],
      triggers: [
        {
          id: 'trigger-1',
          name: 'Webhook Trigger',
          type: 'webhook',
          enabled: true,
          has_auth_method: true,
          webhook_url: 'https://example.com/webhook',
          workflow_id: 'workflow-1',
        },
      ],
      edges: [],
      disabled: false,
      positions: {},
    };

    const positions: Positions = {
      'trigger-1': { x: 100, y: 100 },
    };

    const model = fromWorkflow(
      workflow,
      positions,
      { nodes: [], edges: [] },
      { steps: [] },
      null
    );

    expect(model.nodes).toHaveLength(1);
    const triggerNode = model.nodes[0];

    // Check that trigger data includes has_auth_method
    expect(triggerNode.data.trigger).toBeDefined();
    expect(triggerNode.data.trigger.type).toBe('webhook');
    expect(triggerNode.data.trigger.has_auth_method).toBe(true);
  });

  test('includes has_auth_method in trigger node data for kafka triggers', () => {
    const workflow: Lightning.Workflow = {
      id: 'workflow-1',
      jobs: [],
      triggers: [
        {
          id: 'trigger-1',
          name: 'Kafka Trigger',
          type: 'kafka',
          enabled: true,
          has_auth_method: false,
          workflow_id: 'workflow-1',
        },
      ],
      edges: [],
      disabled: false,
      positions: {},
    };

    const positions: Positions = {
      'trigger-1': { x: 100, y: 100 },
    };

    const model = fromWorkflow(
      workflow,
      positions,
      { nodes: [], edges: [] },
      { steps: [] },
      null
    );

    expect(model.nodes).toHaveLength(1);
    const triggerNode = model.nodes[0];

    // Check that trigger data includes has_auth_method
    expect(triggerNode.data.trigger).toBeDefined();
    expect(triggerNode.data.trigger.type).toBe('kafka');
    expect(triggerNode.data.trigger.has_auth_method).toBe(false);
  });

  test('handles multiple triggers of different types', () => {
    const workflow: Lightning.Workflow = {
      id: 'workflow-1',
      jobs: [],
      triggers: [
        {
          id: 'trigger-1',
          name: 'Webhook',
          type: 'webhook',
          enabled: true,
          has_auth_method: false,
          webhook_url: 'https://example.com/webhook',
          workflow_id: 'workflow-1',
        },
        {
          id: 'trigger-2',
          name: 'Cron',
          type: 'cron',
          enabled: true,
          cron_expression: '*/5 * * * *',
          workflow_id: 'workflow-1',
        },
        {
          id: 'trigger-3',
          name: 'Kafka',
          type: 'kafka',
          enabled: false,
          has_auth_method: true,
          workflow_id: 'workflow-1',
        },
      ],
      edges: [],
      disabled: false,
      positions: {},
    };

    const positions: Positions = {
      'trigger-1': { x: 100, y: 100 },
      'trigger-2': { x: 100, y: 200 },
      'trigger-3': { x: 100, y: 300 },
    };

    const model = fromWorkflow(
      workflow,
      positions,
      { nodes: [], edges: [] },
      { steps: [] },
      null
    );

    expect(model.nodes).toHaveLength(3);

    // Webhook trigger
    const webhookNode = model.nodes.find(n => n.id === 'trigger-1');
    expect(webhookNode?.data.trigger.type).toBe('webhook');
    expect(webhookNode?.data.trigger.has_auth_method).toBe(false);

    // Cron trigger
    const cronNode = model.nodes.find(n => n.id === 'trigger-2');
    expect(cronNode?.data.trigger.type).toBe('cron');
    expect(cronNode?.data.trigger.cron_expression).toBe('*/5 * * * *');

    // Kafka trigger
    const kafkaNode = model.nodes.find(n => n.id === 'trigger-3');
    expect(kafkaNode?.data.trigger.type).toBe('kafka');
    expect(kafkaNode?.data.trigger.has_auth_method).toBe(true);
    expect(kafkaNode?.data.trigger.enabled).toBe(false);
  });

  test('handles cron trigger with empty expression', () => {
    const workflow: Lightning.Workflow = {
      id: 'workflow-1',
      jobs: [],
      triggers: [
        {
          id: 'trigger-1',
          name: 'Cron Trigger',
          type: 'cron',
          enabled: true,
          cron_expression: '',
          workflow_id: 'workflow-1',
        },
      ],
      edges: [],
      disabled: false,
      positions: {},
    };

    const positions: Positions = {
      'trigger-1': { x: 100, y: 100 },
    };

    const model = fromWorkflow(
      workflow,
      positions,
      { nodes: [], edges: [] },
      { steps: [] },
      null
    );

    expect(model.nodes).toHaveLength(1);
    const triggerNode = model.nodes[0];

    // Empty cron_expression should still be included
    expect(triggerNode.data.trigger.type).toBe('cron');
    expect(triggerNode.data.trigger.cron_expression).toBe('');
  });

  test('preserves enabled state for all trigger types', () => {
    const workflow: Lightning.Workflow = {
      id: 'workflow-1',
      jobs: [],
      triggers: [
        {
          id: 'trigger-1',
          name: 'Disabled Webhook',
          type: 'webhook',
          enabled: false,
          has_auth_method: false,
          webhook_url: 'https://example.com/webhook',
          workflow_id: 'workflow-1',
        },
        {
          id: 'trigger-2',
          name: 'Enabled Cron',
          type: 'cron',
          enabled: true,
          cron_expression: '0 0 * * *',
          workflow_id: 'workflow-1',
        },
      ],
      edges: [],
      disabled: false,
      positions: {},
    };

    const positions: Positions = {
      'trigger-1': { x: 100, y: 100 },
      'trigger-2': { x: 100, y: 200 },
    };

    const model = fromWorkflow(
      workflow,
      positions,
      { nodes: [], edges: [] },
      { steps: [] },
      null
    );

    const webhookNode = model.nodes.find(n => n.id === 'trigger-1');
    expect(webhookNode?.data.trigger.enabled).toBe(false);

    const cronNode = model.nodes.find(n => n.id === 'trigger-2');
    expect(cronNode?.data.trigger.enabled).toBe(true);
  });

  test('includes trigger in workflow with jobs and edges', () => {
    const workflow: Lightning.Workflow = {
      id: 'workflow-1',
      jobs: [
        {
          id: 'job-1',
          name: 'First Job',
          workflow_id: 'workflow-1',
          adaptor: '@openfn/language-common@latest',
          body: 'fn(state => state)',
        },
      ],
      triggers: [
        {
          id: 'trigger-1',
          name: 'Cron Trigger',
          type: 'cron',
          enabled: true,
          cron_expression: '0 9 * * 1',
          workflow_id: 'workflow-1',
        },
      ],
      edges: [
        {
          id: 'edge-1',
          name: 'edge-1',
          source_trigger_id: 'trigger-1',
          target_job_id: 'job-1',
          has_auth_method: false,
          condition_type: 'on_job_success',
          errors: {},
        },
      ],
      disabled: false,
      positions: {},
    };

    const positions: Positions = {
      'trigger-1': { x: 100, y: 100 },
      'job-1': { x: 100, y: 200 },
    };

    const model = fromWorkflow(
      workflow,
      positions,
      { nodes: [], edges: [] },
      { steps: [] },
      null
    );

    // Should have trigger, job, and edge
    expect(model.nodes).toHaveLength(2);
    expect(model.edges).toHaveLength(1);

    const triggerNode = model.nodes.find(n => n.id === 'trigger-1');
    expect(triggerNode?.data.trigger.type).toBe('cron');
    expect(triggerNode?.data.trigger.cron_expression).toBe('0 9 * * 1');
  });
});
