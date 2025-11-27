/**
 * Tests for YAMLStateToYDoc
 *
 * This test suite covers the transformation logic for importing YAML WorkflowState
 * into Y.Doc collaborative data structures.
 *
 * Test approach: Tests use the full applyToYDoc flow since Y.Map/Y.Text instances
 * need to be attached to a Y.Doc before they can be accessed.
 */

import { describe, test, expect, beforeEach } from 'vitest';
import * as Y from 'yjs';

import { YAMLStateToYDoc } from '../../../js/collaborative-editor/adapters/YAMLStateToYDoc';
import type { WorkflowState as YAMLWorkflowState } from '../../../js/yaml/types';
import type { Session } from '../../../js/collaborative-editor/types/session';

describe('YAMLStateToYDoc', () => {
  let ydoc: Session.WorkflowDoc;

  beforeEach(() => {
    ydoc = new Y.Doc() as Session.WorkflowDoc;
  });

  describe('Job transformations', () => {
    test('transforms basic job with all required fields', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'workflow-test',
        name: 'Test',
        jobs: [
          {
            id: 'job-123',
            name: 'Fetch Data',
            adaptor: '@openfn/language-http@latest',
            body: "get('/api/data')",
          },
        ],
        triggers: [],
        edges: [],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      const jobsArray = ydoc.getArray('jobs');
      const jobMap = jobsArray.get(0) as Y.Map<unknown>;

      expect(jobMap.get('id')).toBe('job-123');
      expect(jobMap.get('name')).toBe('Fetch Data');
      expect(jobMap.get('adaptor')).toBe('@openfn/language-http@latest');

      // Body should be Y.Text
      const bodyText = jobMap.get('body');
      expect(bodyText).toBeInstanceOf(Y.Text);
      expect(bodyText.toString()).toBe("get('/api/data')");

      // Enabled should default to true
      expect(jobMap.get('enabled')).toBe(true);
    });

    test('preserves empty ID when provided', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'workflow-test',
        name: 'Test',
        jobs: [
          {
            id: '',
            name: 'Test Job',
            adaptor: '@openfn/language-common@latest',
            body: 'fn()',
          },
        ],
        triggers: [],
        edges: [],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      const jobsArray = ydoc.getArray('jobs');
      const jobMap = jobsArray.get(0) as Y.Map<unknown>;
      const id = jobMap.get('id') as string;

      expect(id).toBe('');
    });

    test('handles empty body', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'workflow-test',
        name: 'Test',
        jobs: [
          {
            id: 'job-empty',
            name: 'Empty Job',
            adaptor: '@openfn/language-common@latest',
            body: '',
          },
        ],
        triggers: [],
        edges: [],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      const jobsArray = ydoc.getArray('jobs');
      const jobMap = jobsArray.get(0) as Y.Map<unknown>;
      const bodyText = jobMap.get('body') as Y.Text;

      expect(bodyText.toString()).toBe('');
    });

    test('handles multiline body', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'workflow-test',
        name: 'Test',
        jobs: [
          {
            id: 'job-multiline',
            name: 'Multiline Job',
            adaptor: '@openfn/language-common@latest',
            body: 'fn(state => {\n  console.log(state);\n  return state;\n});',
          },
        ],
        triggers: [],
        edges: [],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      const jobsArray = ydoc.getArray('jobs');
      const jobMap = jobsArray.get(0) as Y.Map<unknown>;
      const bodyText = jobMap.get('body') as Y.Text;

      expect(bodyText.toString()).toBe(
        'fn(state => {\n  console.log(state);\n  return state;\n});'
      );
    });
  });

  describe('Trigger transformations', () => {
    test('transforms cron trigger with expression', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'workflow-test',
        name: 'Test',
        jobs: [],
        triggers: [
          {
            id: 'trigger-cron',
            type: 'cron',
            enabled: true,
            cron_expression: '0 0 * * *',
          },
        ],
        edges: [],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      const triggersArray = ydoc.getArray('triggers');
      const triggerMap = triggersArray.get(0) as Y.Map<unknown>;

      expect(triggerMap.get('id')).toBe('trigger-cron');
      expect(triggerMap.get('enabled')).toBe(true);
      expect(triggerMap.get('cron_expression')).toBe('0 0 * * *');
    });

    test('transforms webhook trigger with null cron_expression', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'workflow-test',
        name: 'Test',
        jobs: [],
        triggers: [
          {
            id: 'trigger-webhook',
            type: 'webhook',
            enabled: true,
          },
        ],
        edges: [],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      const triggersArray = ydoc.getArray('triggers');
      const triggerMap = triggersArray.get(0) as Y.Map<unknown>;

      expect(triggerMap.get('id')).toBe('trigger-webhook');
      expect(triggerMap.get('enabled')).toBe(true);
      // Webhook triggers should default cron_expression to null
      expect(triggerMap.get('cron_expression')).toBeNull();
    });

    test('transforms kafka trigger with null cron_expression', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'workflow-test',
        name: 'Test',
        jobs: [],
        triggers: [
          {
            id: 'trigger-kafka',
            type: 'kafka',
            enabled: false,
          },
        ],
        edges: [],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      const triggersArray = ydoc.getArray('triggers');
      const triggerMap = triggersArray.get(0) as Y.Map<unknown>;

      expect(triggerMap.get('id')).toBe('trigger-kafka');
      expect(triggerMap.get('enabled')).toBe(false);
      expect(triggerMap.get('cron_expression')).toBeNull();
    });

    test('preserves empty ID when provided', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'workflow-test',
        name: 'Test',
        jobs: [],
        triggers: [
          {
            id: '',
            type: 'webhook',
            enabled: true,
          },
        ],
        edges: [],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      const triggersArray = ydoc.getArray('triggers');
      const triggerMap = triggersArray.get(0) as Y.Map<unknown>;
      const id = triggerMap.get('id') as string;

      expect(id).toBe('');
    });
  });

  describe('Edge transformations', () => {
    test('transforms edge with all fields', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'workflow-test',
        name: 'Test',
        jobs: [],
        triggers: [],
        edges: [
          {
            id: 'edge-123',
            source_trigger_id: 'trigger-1',
            source_job_id: '',
            target_job_id: 'job-2',
            condition_type: 'always',
            condition_label: 'Always run',
            condition_expression: '',
            enabled: true,
          },
        ],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      const edgesArray = ydoc.getArray('edges');
      const edgeMap = edgesArray.get(0) as Y.Map<unknown>;

      expect(edgeMap.get('id')).toBe('edge-123');
      expect(edgeMap.get('source_trigger_id')).toBe('trigger-1');
      expect(edgeMap.get('source_job_id')).toBeNull();
      expect(edgeMap.get('target_job_id')).toBe('job-2');
      expect(edgeMap.get('condition_type')).toBe('always');
      expect(edgeMap.get('condition_label')).toBe('Always run');
      expect(edgeMap.get('condition_expression')).toBeNull();
      expect(edgeMap.get('enabled')).toBe(true);
    });

    test('defaults optional fields to null', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'workflow-test',
        name: 'Test',
        jobs: [],
        triggers: [],
        edges: [
          {
            id: 'edge-minimal',
            target_job_id: 'job-1',
            condition_type: 'on_job_success',
            enabled: true,
          },
        ],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      const edgesArray = ydoc.getArray('edges');
      const edgeMap = edgesArray.get(0) as Y.Map<unknown>;

      expect(edgeMap.get('source_trigger_id')).toBeNull();
      expect(edgeMap.get('source_job_id')).toBeNull();
      expect(edgeMap.get('condition_label')).toBeNull();
      expect(edgeMap.get('condition_expression')).toBeNull();
    });

    test('handles null condition_expression', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'workflow-test',
        name: 'Test',
        jobs: [],
        triggers: [],
        edges: [
          {
            id: 'edge-null',
            target_job_id: 'job-1',
            condition_type: 'js_expression',
            condition_expression: null,
            enabled: true,
          },
        ],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      const edgesArray = ydoc.getArray('edges');
      const edgeMap = edgesArray.get(0) as Y.Map<unknown>;

      expect(edgeMap.get('condition_expression')).toBeNull();
    });

    test('preserves empty ID when provided', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'workflow-test',
        name: 'Test',
        jobs: [],
        triggers: [],
        edges: [
          {
            id: '',
            target_job_id: 'job-1',
            condition_type: 'always',
            enabled: true,
          },
        ],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      const edgesArray = ydoc.getArray('edges');
      const edgeMap = edgesArray.get(0) as Y.Map<unknown>;
      const id = edgeMap.get('id') as string;

      expect(id).toBe('');
    });
  });

  describe('applyToYDoc full workflow', () => {
    test('applies complete workflow state to Y.Doc', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'workflow-123',
        name: 'Test Workflow',
        jobs: [
          {
            id: 'job-1',
            name: 'First Job',
            adaptor: '@openfn/language-http@latest',
            body: "get('/api/data')",
          },
        ],
        triggers: [
          {
            id: 'trigger-1',
            type: 'webhook',
            enabled: true,
          },
        ],
        edges: [
          {
            id: 'edge-1',
            source_trigger_id: 'trigger-1',
            target_job_id: 'job-1',
            condition_type: 'always',
            enabled: true,
          },
        ],
        positions: {
          'trigger-1': { x: 100, y: 100 },
          'job-1': { x: 300, y: 100 },
        },
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      // Check workflow metadata (note: id is not set by applyToYDoc)
      const workflowMap = ydoc.getMap('workflow');
      expect(workflowMap.get('name')).toBe('Test Workflow');

      // Check jobs
      const jobsArray = ydoc.getArray('jobs');
      expect(jobsArray.length).toBe(1);
      const job = jobsArray.get(0) as Y.Map<unknown>;
      expect(job.get('id')).toBe('job-1');
      expect(job.get('name')).toBe('First Job');

      // Check triggers
      const triggersArray = ydoc.getArray('triggers');
      expect(triggersArray.length).toBe(1);
      const trigger = triggersArray.get(0) as Y.Map<unknown>;
      expect(trigger.get('id')).toBe('trigger-1');

      // Check edges
      const edgesArray = ydoc.getArray('edges');
      expect(edgesArray.length).toBe(1);
      const edge = edgesArray.get(0) as Y.Map<unknown>;
      expect(edge.get('id')).toBe('edge-1');

      // Check positions
      const positionsMap = ydoc.getMap('positions');
      expect(positionsMap.get('trigger-1')).toEqual({ x: 100, y: 100 });
      expect(positionsMap.get('job-1')).toEqual({ x: 300, y: 100 });
    });

    test('handles empty workflow', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'empty-workflow',
        name: 'Empty Workflow',
        jobs: [],
        triggers: [],
        edges: [],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      const workflowMap = ydoc.getMap('workflow');
      expect(workflowMap.get('name')).toBe('Empty Workflow');

      expect(ydoc.getArray('jobs').length).toBe(0);
      expect(ydoc.getArray('triggers').length).toBe(0);
      expect(ydoc.getArray('edges').length).toBe(0);

      const positionsMap = ydoc.getMap('positions');
      expect(positionsMap.size).toBe(0);
    });

    test('clears existing Y.Doc data before import', () => {
      // Populate Y.Doc with initial data
      const initialWorkflow: YAMLWorkflowState = {
        id: 'initial',
        name: 'Initial',
        jobs: [
          {
            id: 'old-job',
            name: 'Old',
            adaptor: '@openfn/language-common@latest',
            body: 'old()',
          },
        ],
        triggers: [],
        edges: [],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, initialWorkflow);
      expect(ydoc.getArray('jobs').length).toBe(1);

      // Import new workflow
      const newWorkflow: YAMLWorkflowState = {
        id: 'new',
        name: 'New',
        jobs: [
          {
            id: 'new-job',
            name: 'New',
            adaptor: '@openfn/language-common@latest',
            body: 'new()',
          },
        ],
        triggers: [],
        edges: [],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, newWorkflow);

      // Old data should be replaced
      const jobsArray = ydoc.getArray('jobs');
      expect(jobsArray.length).toBe(1);
      const job = jobsArray.get(0) as Y.Map<unknown>;
      expect(job.get('id')).toBe('new-job');
    });

    test('does not set workflow ID', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'some-id',
        name: 'No ID Workflow',
        jobs: [],
        triggers: [],
        edges: [],
        positions: null,
      };

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      const workflowMap = ydoc.getMap('workflow');
      const id = workflowMap.get('id');

      expect(id).toBeUndefined();
    });

    test('applies all transformations in single transaction', () => {
      const workflowState: YAMLWorkflowState = {
        id: 'atomic-test',
        name: 'Atomic Test',
        jobs: [
          {
            id: 'job-1',
            name: 'Job 1',
            adaptor: '@openfn/language-common@latest',
            body: 'fn1()',
          },
          {
            id: 'job-2',
            name: 'Job 2',
            adaptor: '@openfn/language-common@latest',
            body: 'fn2()',
          },
        ],
        triggers: [{ id: 'trigger-1', type: 'webhook', enabled: true }],
        edges: [
          {
            id: 'edge-1',
            source_trigger_id: 'trigger-1',
            target_job_id: 'job-1',
            condition_type: 'always',
            enabled: true,
          },
          {
            id: 'edge-2',
            source_job_id: 'job-1',
            target_job_id: 'job-2',
            condition_type: 'on_job_success',
            enabled: true,
          },
        ],
        positions: {
          'trigger-1': { x: 0, y: 0 },
          'job-1': { x: 200, y: 0 },
          'job-2': { x: 400, y: 0 },
        },
      };

      let transactionCount = 0;
      ydoc.on('update', () => {
        transactionCount++;
      });

      YAMLStateToYDoc.applyToYDoc(ydoc, workflowState);

      // Should be a single transaction (single update event)
      expect(transactionCount).toBe(1);

      // Verify all data was applied
      expect(ydoc.getArray('jobs').length).toBe(2);
      expect(ydoc.getArray('triggers').length).toBe(1);
      expect(ydoc.getArray('edges').length).toBe(2);
      expect(ydoc.getMap('positions').size).toBe(3);
    });
  });
});
