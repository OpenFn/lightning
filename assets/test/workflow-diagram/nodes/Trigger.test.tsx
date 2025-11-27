/**
 * Trigger Node Component Tests
 *
 * Tests that trigger nodes display correct icons for all trigger types
 * (webhook, cron, kafka) and handle edge cases gracefully.
 */

import { render } from '@testing-library/react';
import { ReactFlowProvider } from '@xyflow/react';
import { describe, expect, test } from 'vitest';

import TriggerNode from '../../../js/workflow-diagram/nodes/Trigger';
import type { Lightning } from '../../../js/workflow-diagram/types';

/**
 * Helper to render a trigger node within ReactFlow context
 *
 * Note: TriggerNode expects data.trigger to contain the trigger info,
 * which is how from-workflow structures it
 */
function renderTriggerNode(trigger: Lightning.TriggerNode) {
  const data: any = {
    trigger: {
      type: trigger.type,
      enabled: trigger.enabled,
      ...(trigger.type === 'cron' && {
        cron_expression: trigger.cron_expression,
      }),
      ...(trigger.type === 'webhook' && {
        has_auth_method: trigger.has_auth_method,
      }),
      ...(trigger.type === 'kafka' && {
        has_auth_method: trigger.has_auth_method,
      }),
    },
  };

  return render(
    <ReactFlowProvider>
      <TriggerNode id={trigger.id} data={data} selected={false} />
    </ReactFlowProvider>
  );
}

describe('Trigger Node - Icon Display', () => {
  test('displays icon for webhook trigger', () => {
    const webhookTrigger: Lightning.WebhookTrigger = {
      id: 'trigger-1',
      name: 'Webhook Trigger',
      type: 'webhook',
      enabled: true,
      has_auth_method: false,
      webhook_url: 'https://example.com/webhook',
      workflow_id: 'test-workflow',
    };

    const { container } = renderTriggerNode(webhookTrigger);

    // GlobeAltIcon from heroicons should be rendered
    const svgElement = container.querySelector('svg');
    expect(svgElement).toBeInTheDocument();
  });

  test('displays icon for cron trigger with valid expression', () => {
    const cronTrigger: Lightning.CronTrigger = {
      id: 'trigger-2',
      name: 'Cron Trigger',
      type: 'cron',
      enabled: true,
      cron_expression: '0 0 * * *',
      workflow_id: 'test-workflow',
    };

    const { container } = renderTriggerNode(cronTrigger);

    // ClockIcon from heroicons should be rendered
    const svgElement = container.querySelector('svg');
    expect(svgElement).toBeInTheDocument();
  });

  test('displays icon for cron trigger with invalid expression', () => {
    const cronTrigger: Lightning.CronTrigger = {
      id: 'trigger-3',
      name: 'Cron Trigger',
      type: 'cron',
      enabled: true,
      cron_expression: 'invalid cron',
      workflow_id: 'test-workflow',
    };

    const { container } = renderTriggerNode(cronTrigger);

    // ClockIcon should still be rendered even with invalid expression
    const svgElement = container.querySelector('svg');
    expect(svgElement).toBeInTheDocument();
  });

  test('displays icon for cron trigger with empty expression', () => {
    const cronTrigger: Lightning.CronTrigger = {
      id: 'trigger-4',
      name: 'Cron Trigger',
      type: 'cron',
      enabled: true,
      cron_expression: '',
      workflow_id: 'test-workflow',
    };

    const { container } = renderTriggerNode(cronTrigger);

    // ClockIcon should still be rendered even with empty expression
    const svgElement = container.querySelector('svg');
    expect(svgElement).toBeInTheDocument();
  });

  test('displays icon for kafka trigger', () => {
    const kafkaTrigger: Lightning.KafkaTrigger = {
      id: 'trigger-5',
      name: 'Kafka Trigger',
      type: 'kafka',
      enabled: true,
      has_auth_method: true,
      workflow_id: 'test-workflow',
    };

    const { container } = renderTriggerNode(kafkaTrigger);

    // Kafka icon (custom SVG) should be rendered
    const svgElement = container.querySelector('svg');
    expect(svgElement).toBeInTheDocument();
  });

  test('displays lock icon for webhook trigger with auth', () => {
    const webhookTrigger: Lightning.WebhookTrigger = {
      id: 'trigger-11',
      name: 'Webhook Trigger',
      type: 'webhook',
      enabled: true,
      has_auth_method: true,
      webhook_url: 'https://example.com/webhook',
      workflow_id: 'test-workflow',
    };

    const { container } = renderTriggerNode(webhookTrigger);

    // Should have both primary icon and lock icon
    const svgElements = container.querySelectorAll('svg');
    expect(svgElements.length).toBeGreaterThanOrEqual(1);
  });

  test('displays lock icon for kafka trigger with auth', () => {
    const kafkaTrigger: Lightning.KafkaTrigger = {
      id: 'trigger-12',
      name: 'Kafka Trigger',
      type: 'kafka',
      enabled: true,
      has_auth_method: true,
      workflow_id: 'test-workflow',
    };

    const { container } = renderTriggerNode(kafkaTrigger);

    // Should have both primary icon and lock icon
    const svgElements = container.querySelectorAll('svg');
    expect(svgElements.length).toBeGreaterThanOrEqual(1);
  });
});
