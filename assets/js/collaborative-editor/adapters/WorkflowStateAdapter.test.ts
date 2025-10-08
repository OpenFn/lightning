import { describe, it, expect, beforeEach } from 'vitest';
import * as Y from 'yjs';
import { WorkflowStateAdapter } from './WorkflowStateAdapter';
import type { WorkflowState, StateJob, StateTrigger, StateEdge } from '../../yaml/types';

describe('WorkflowStateAdapter', () => {
  describe('transformJob', () => {
    it('should transform a StateJob to Y.Doc Job Map with all fields', () => {
      const job: StateJob = {
        id: 'job-1',
        name: 'Test Job',
        adaptor: '@openfn/language-http@latest',
        body: 'fn(state => state)',
      };

      const jobMap = WorkflowStateAdapter.transformJob(job);

      expect(jobMap.get('id')).toBe('job-1');
      expect(jobMap.get('name')).toBe('Test Job');
      expect(jobMap.get('adaptor')).toBe('@openfn/language-http@latest');
      expect(jobMap.get('enabled')).toBe(true);

      const body = jobMap.get('body');
      expect(body).toBeInstanceOf(Y.Text);
      expect(body?.toString()).toBe('fn(state => state)');
    });

    it('should generate ID if missing', () => {
      const job = {
        name: 'Test Job',
        adaptor: '@openfn/language-http@latest',
        body: '',
      } as StateJob;

      const jobMap = WorkflowStateAdapter.transformJob(job);
      const id = jobMap.get('id');

      expect(id).toBeTruthy();
      expect(typeof id).toBe('string');
      expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
    });

    it('should convert empty body to Y.Text', () => {
      const job: StateJob = {
        id: 'job-1',
        name: 'Test Job',
        adaptor: '@openfn/language-http@latest',
        body: '',
      };

      const jobMap = WorkflowStateAdapter.transformJob(job);
      const body = jobMap.get('body');

      expect(body).toBeInstanceOf(Y.Text);
      expect(body?.toString()).toBe('');
    });

    it('should always add enabled=true', () => {
      const job: StateJob = {
        id: 'job-1',
        name: 'Test Job',
        adaptor: '@openfn/language-http@latest',
        body: '',
      };

      const jobMap = WorkflowStateAdapter.transformJob(job);
      expect(jobMap.get('enabled')).toBe(true);
    });
  });

  describe('transformTrigger', () => {
    it('should transform a cron trigger with cron_expression', () => {
      const trigger: StateTrigger = {
        id: 'trigger-1',
        type: 'cron',
        enabled: true,
        cron_expression: '0 0 * * *',
      };

      const triggerMap = WorkflowStateAdapter.transformTrigger(trigger);

      expect(triggerMap.get('id')).toBe('trigger-1');
      expect(triggerMap.get('enabled')).toBe(true);
      expect(triggerMap.get('cron_expression')).toBe('0 0 * * *');
    });

    it('should default cron_expression to empty string for webhook trigger', () => {
      const trigger: StateTrigger = {
        id: 'trigger-1',
        type: 'webhook',
        enabled: true,
      };

      const triggerMap = WorkflowStateAdapter.transformTrigger(trigger);

      expect(triggerMap.get('id')).toBe('trigger-1');
      expect(triggerMap.get('enabled')).toBe(true);
      expect(triggerMap.get('cron_expression')).toBe('');
    });

    it('should default cron_expression to empty string for kafka trigger', () => {
      const trigger: StateTrigger = {
        id: 'trigger-1',
        type: 'kafka',
        enabled: true,
      };

      const triggerMap = WorkflowStateAdapter.transformTrigger(trigger);

      expect(triggerMap.get('cron_expression')).toBe('');
    });

    it('should generate ID if missing', () => {
      const trigger = {
        type: 'webhook',
        enabled: true,
      } as StateTrigger;

      const triggerMap = WorkflowStateAdapter.transformTrigger(trigger);
      const id = triggerMap.get('id');

      expect(id).toBeTruthy();
      expect(typeof id).toBe('string');
    });
  });

  describe('transformEdge', () => {
    it('should transform an edge with all fields', () => {
      const edge: StateEdge = {
        id: 'edge-1',
        source_job_id: 'job-1',
        source_trigger_id: '',
        target_job_id: 'job-2',
        condition_type: 'on_job_success',
        condition_label: 'Success',
        condition_expression: '',
        enabled: true,
      };

      const edgeMap = WorkflowStateAdapter.transformEdge(edge);

      expect(edgeMap.get('id')).toBe('edge-1');
      expect(edgeMap.get('source_job_id')).toBe('job-1');
      expect(edgeMap.get('source_trigger_id')).toBe('');
      expect(edgeMap.get('target_job_id')).toBe('job-2');
      expect(edgeMap.get('condition_type')).toBe('on_job_success');
      expect(edgeMap.get('condition_label')).toBe('Success');
      expect(edgeMap.get('condition_expression')).toBe('');
      expect(edgeMap.get('enabled')).toBe(true);
    });

    it('should default optional fields to empty strings', () => {
      const edge: StateEdge = {
        id: 'edge-1',
        target_job_id: 'job-2',
        condition_type: 'always',
        enabled: true,
      };

      const edgeMap = WorkflowStateAdapter.transformEdge(edge);

      expect(edgeMap.get('source_job_id')).toBe('');
      expect(edgeMap.get('source_trigger_id')).toBe('');
      expect(edgeMap.get('condition_label')).toBe('');
      expect(edgeMap.get('condition_expression')).toBe('');
    });

    it('should generate ID if missing', () => {
      const edge = {
        target_job_id: 'job-2',
        condition_type: 'always',
        enabled: true,
      } as StateEdge;

      const edgeMap = WorkflowStateAdapter.transformEdge(edge);
      const id = edgeMap.get('id');

      expect(id).toBeTruthy();
      expect(typeof id).toBe('string');
    });
  });

  describe('applyToYDoc', () => {
    let ydoc: any; // Use any to avoid complex Y.Doc typing issues in tests

    beforeEach(() => {
      ydoc = new Y.Doc();
    });

    it('should apply a complete workflow state to Y.Doc', () => {
      const workflowState: WorkflowState = {
        id: 'workflow-1',
        name: 'Test Workflow',
        jobs: [
          {
            id: 'job-1',
            name: 'Job 1',
            adaptor: '@openfn/language-http@latest',
            body: 'fn(state => state)',
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
          'job-1': { x: 100, y: 200 },
          'trigger-1': { x: 50, y: 100 },
        },
      };

      WorkflowStateAdapter.applyToYDoc(ydoc, workflowState);

      // Check workflow metadata
      const workflowMap = ydoc.getMap('workflow');
      expect(workflowMap.get('id')).toBe('workflow-1');
      expect(workflowMap.get('name')).toBe('Test Workflow');

      // Check jobs
      const jobsArray = ydoc.getArray('jobs');
      expect(jobsArray.length).toBe(1);
      const job = jobsArray.get(0) as Y.Map<unknown>;
      expect(job.get('id')).toBe('job-1');
      expect(job.get('name')).toBe('Job 1');

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
      expect(positionsMap.get('job-1')).toEqual({ x: 100, y: 200 });
      expect(positionsMap.get('trigger-1')).toEqual({ x: 50, y: 100 });
    });

    it('should clear existing data before importing', () => {
      // Set up initial data
      const jobsArray = ydoc.getArray('jobs');
      const jobMap = new Y.Map();
      jobMap.set('id', 'old-job');
      jobsArray.push([jobMap]);

      expect(jobsArray.length).toBe(1);

      // Import new workflow
      const workflowState: WorkflowState = {
        id: 'workflow-1',
        name: 'Test Workflow',
        jobs: [],
        triggers: [],
        edges: [],
        positions: null,
      };

      WorkflowStateAdapter.applyToYDoc(ydoc, workflowState);

      // Check that old data was cleared
      expect(jobsArray.length).toBe(0);
    });

    it('should generate workflow ID if missing', () => {
      const workflowState = {
        name: 'Test Workflow',
        jobs: [],
        triggers: [],
        edges: [],
        positions: null,
      } as unknown as WorkflowState;

      WorkflowStateAdapter.applyToYDoc(ydoc, workflowState);

      const workflowMap = ydoc.getMap('workflow');
      const id = workflowMap.get('id');

      expect(id).toBeTruthy();
      expect(typeof id).toBe('string');
    });

    it('should handle null positions', () => {
      const workflowState: WorkflowState = {
        id: 'workflow-1',
        name: 'Test Workflow',
        jobs: [],
        triggers: [],
        edges: [],
        positions: null,
      };

      WorkflowStateAdapter.applyToYDoc(ydoc, workflowState);

      const positionsMap = ydoc.getMap('positions');
      expect(positionsMap.size).toBe(0);
    });

    it('should handle empty positions object', () => {
      const workflowState: WorkflowState = {
        id: 'workflow-1',
        name: 'Test Workflow',
        jobs: [],
        triggers: [],
        edges: [],
        positions: {},
      };

      WorkflowStateAdapter.applyToYDoc(ydoc, workflowState);

      const positionsMap = ydoc.getMap('positions');
      expect(positionsMap.size).toBe(0);
    });

    it('should perform import in a single transaction', () => {
      let transactionCount = 0;

      ydoc.on('beforeTransaction', () => {
        transactionCount++;
      });

      const workflowState: WorkflowState = {
        id: 'workflow-1',
        name: 'Test Workflow',
        jobs: [
          { id: 'job-1', name: 'Job 1', adaptor: '@openfn/language-http@latest', body: '' },
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
        ],
        positions: { 'job-1': { x: 100, y: 200 } },
      };

      WorkflowStateAdapter.applyToYDoc(ydoc, workflowState);

      // Should only trigger one transaction for the entire import
      expect(transactionCount).toBe(1);
    });
  });
});
