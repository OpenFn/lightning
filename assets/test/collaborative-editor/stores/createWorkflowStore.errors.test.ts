import { beforeEach, describe, expect, it } from 'vitest';
import * as Y from 'yjs';
import { createWorkflowStore } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Session } from '../../../js/collaborative-editor/types/session';

describe('WorkflowStore - Errors Observer (Phase 3: Denormalized)', () => {
  let ydoc: Y.Doc;
  let store: ReturnType<typeof createWorkflowStore>;

  beforeEach(() => {
    ydoc = new Y.Doc();

    // Initialize Y.Doc structure
    const workflowMap = ydoc.getMap('workflow');
    const jobsArray = ydoc.getArray('jobs');
    const triggersArray = ydoc.getArray('triggers');
    const edgesArray = ydoc.getArray('edges');
    const positionsMap = ydoc.getMap('positions');
    const errorsMap = ydoc.getMap('errors');

    ydoc.transact(() => {
      workflowMap.set('id', 'workflow-1');
      workflowMap.set('name', 'Test Workflow');
      workflowMap.set('lock_version', 1);
      workflowMap.set('deleted_at', null);
      workflowMap.set('concurrency', null);
      workflowMap.set('enable_job_logs', false);
    });

    store = createWorkflowStore();

    // Create mock provider with channel methods
    const mockProvider = {
      channel: {
        on: () => {},
        off: () => {},
      },
    } as any;

    store.connect(ydoc as Session.WorkflowDoc, mockProvider);
  });

  describe('Workflow errors denormalization', () => {
    it('should denormalize workflow errors onto workflow object', () => {
      const errorsMap = ydoc.getMap('errors');

      // Set nested workflow errors in Y.Doc
      ydoc.transact(() => {
        errorsMap.set('workflow', { name: ['Name is required'] });
      });

      // Observer should denormalize onto workflow entity
      const state = store.getSnapshot();
      expect(state.workflow?.errors).toEqual({ name: ['Name is required'] });
    });

    it('should handle multiple workflow errors', () => {
      const errorsMap = ydoc.getMap('errors');

      // Set multiple workflow errors
      ydoc.transact(() => {
        errorsMap.set('workflow', {
          name: ['Name is required'],
          concurrency: ['Must be positive'],
        });
      });

      const state = store.getSnapshot();
      expect(state.workflow?.errors).toEqual({
        name: ['Name is required'],
        concurrency: ['Must be positive'],
      });
    });

    it('should clear workflow errors when removed from Y.Doc', () => {
      const errorsMap = ydoc.getMap('errors');

      // Add workflow errors
      ydoc.transact(() => {
        errorsMap.set('workflow', { name: ['Name is required'] });
      });

      expect(store.getSnapshot().workflow?.errors).toEqual({
        name: ['Name is required'],
      });

      // Clear workflow errors
      ydoc.transact(() => {
        errorsMap.set('workflow', {});
      });

      // Errors should be empty object
      expect(store.getSnapshot().workflow?.errors).toEqual({});
    });
  });

  describe('Job errors denormalization', () => {
    beforeEach(() => {
      // Add a job to test with
      const jobsArray = ydoc.getArray('jobs');
      const jobMap = new Y.Map();

      ydoc.transact(() => {
        jobMap.set('id', 'job-123');
        jobMap.set('name', 'Test Job');
        jobMap.set('body', new Y.Text('fn(state => state)'));
        jobMap.set('adaptor', '@openfn/language-common@latest');
        jobMap.set('enabled', true);
        jobMap.set('project_credential_id', null);
        jobMap.set('keychain_credential_id', null);
        jobsArray.push([jobMap]);
      });
    });

    it('should denormalize job errors onto job object', () => {
      const errorsMap = ydoc.getMap('errors');

      // Set nested job errors in Y.Doc
      ydoc.transact(() => {
        errorsMap.set('jobs', {
          'job-123': { name: ['Job name is too long'] },
        });
      });

      // Observer should denormalize onto job entity
      const state = store.getSnapshot();
      const job = state.jobs.find(j => j.id === 'job-123');
      expect(job?.errors).toEqual({ name: ['Job name is too long'] });
    });

    it('should handle multiple errors on same job', () => {
      const errorsMap = ydoc.getMap('errors');

      ydoc.transact(() => {
        errorsMap.set('jobs', {
          'job-123': {
            name: ['Job name is too long'],
            adaptor: ['Adaptor not found'],
          },
        });
      });

      const state = store.getSnapshot();
      const job = state.jobs.find(j => j.id === 'job-123');
      expect(job?.errors).toEqual({
        name: ['Job name is too long'],
        adaptor: ['Adaptor not found'],
      });
    });

    it('should clear job errors when removed from Y.Doc', () => {
      const errorsMap = ydoc.getMap('errors');

      // Add job errors
      ydoc.transact(() => {
        errorsMap.set('jobs', {
          'job-123': { name: ['Job name is too long'] },
        });
      });

      const job1 = store.getSnapshot().jobs.find(j => j.id === 'job-123');
      expect(job1?.errors).toEqual({ name: ['Job name is too long'] });

      // Clear job errors
      ydoc.transact(() => {
        errorsMap.set('jobs', {});
      });

      const job2 = store.getSnapshot().jobs.find(j => j.id === 'job-123');
      expect(job2?.errors).toEqual({});
    });

    it('should only update affected jobs (referential stability)', () => {
      // Add second job
      const jobsArray = ydoc.getArray('jobs');
      const job2Map = new Y.Map();

      ydoc.transact(() => {
        job2Map.set('id', 'job-456');
        job2Map.set('name', 'Another Job');
        job2Map.set('body', new Y.Text('fn(state => state)'));
        job2Map.set('adaptor', '@openfn/language-common@latest');
        job2Map.set('enabled', true);
        job2Map.set('project_credential_id', null);
        job2Map.set('keychain_credential_id', null);
        jobsArray.push([job2Map]);
      });

      const stateBefore = store.getSnapshot();
      const job1Before = stateBefore.jobs.find(j => j.id === 'job-123');
      const job2Before = stateBefore.jobs.find(j => j.id === 'job-456');

      // Add error to job-123 only
      const errorsMap = ydoc.getMap('errors');
      ydoc.transact(() => {
        errorsMap.set('jobs', {
          'job-123': { name: ['Error on job 1'] },
        });
      });

      const stateAfter = store.getSnapshot();
      const job1After = stateAfter.jobs.find(j => j.id === 'job-123');
      const job2After = stateAfter.jobs.find(j => j.id === 'job-456');

      // job-123 should have new reference (error added)
      expect(job1After).not.toBe(job1Before);
      expect(job1After?.errors).toEqual({ name: ['Error on job 1'] });

      // job-456 should have same reference (no error change)
      expect(job2After).toBe(job2Before);
      expect(job2After?.errors).toBeUndefined();
    });
  });

  describe('Trigger errors denormalization', () => {
    beforeEach(() => {
      // Add a trigger to test with
      const triggersArray = ydoc.getArray('triggers');
      const triggerMap = new Y.Map();

      ydoc.transact(() => {
        triggerMap.set('id', 'trigger-789');
        triggerMap.set('cron_expression', '0 * * * *');
        triggerMap.set('enabled', true);
        triggersArray.push([triggerMap]);
      });
    });

    it('should denormalize trigger errors onto trigger object', () => {
      const errorsMap = ydoc.getMap('errors');

      ydoc.transact(() => {
        errorsMap.set('triggers', {
          'trigger-789': { cron_expression: ['Invalid cron expression'] },
        });
      });

      const state = store.getSnapshot();
      const trigger = state.triggers.find(t => t.id === 'trigger-789');
      expect(trigger?.errors).toEqual({
        cron_expression: ['Invalid cron expression'],
      });
    });
  });

  describe('Edge errors denormalization', () => {
    beforeEach(() => {
      // Add an edge to test with
      const edgesArray = ydoc.getArray('edges');
      const edgeMap = new Y.Map();

      ydoc.transact(() => {
        edgeMap.set('id', 'edge-abc');
        edgeMap.set('source_job_id', 'job-1');
        edgeMap.set('source_trigger_id', null);
        edgeMap.set('target_job_id', 'job-2');
        edgeMap.set('condition_type', 'on_job_success');
        edgeMap.set('condition_label', null);
        edgeMap.set('condition_expression', null);
        edgeMap.set('enabled', true);
        edgesArray.push([edgeMap]);
      });
    });

    it('should denormalize edge errors onto edge object', () => {
      const errorsMap = ydoc.getMap('errors');

      ydoc.transact(() => {
        errorsMap.set('edges', {
          'edge-abc': { condition_expression: ['Invalid expression'] },
        });
      });

      const state = store.getSnapshot();
      const edge = state.edges.find(e => e.id === 'edge-abc');
      expect(edge?.errors).toEqual({
        condition_expression: ['Invalid expression'],
      });
    });
  });

  describe('Error state preservation during Y.Doc updates', () => {
    beforeEach(() => {
      // Add a job and edge to test with
      const jobsArray = ydoc.getArray('jobs');
      const jobMap = new Y.Map();

      ydoc.transact(() => {
        jobMap.set('id', 'job-123');
        jobMap.set('name', 'Test Job');
        jobMap.set('body', new Y.Text('fn(state => state)'));
        jobMap.set('adaptor', '@openfn/language-common@latest');
        jobMap.set('enabled', true);
        jobMap.set('project_credential_id', null);
        jobMap.set('keychain_credential_id', null);
        jobsArray.push([jobMap]);
      });

      const edgesArray = ydoc.getArray('edges');
      const edgeMap = new Y.Map();

      ydoc.transact(() => {
        edgeMap.set('id', 'edge-abc');
        edgeMap.set('source_job_id', 'job-1');
        edgeMap.set('source_trigger_id', null);
        edgeMap.set('target_job_id', 'job-2');
        edgeMap.set('condition_type', 'on_job_success');
        edgeMap.set('condition_label', null);
        edgeMap.set('condition_expression', null);
        edgeMap.set('enabled', true);
        edgesArray.push([edgeMap]);
      });

      const triggersArray = ydoc.getArray('triggers');
      const triggerMap = new Y.Map();

      ydoc.transact(() => {
        triggerMap.set('id', 'trigger-789');
        triggerMap.set('cron_expression', '0 * * * *');
        triggerMap.set('enabled', true);
        triggersArray.push([triggerMap]);
      });
    });

    it('should preserve job errors when jobs array is updated', () => {
      const errorsMap = ydoc.getMap('errors');

      // Set job errors
      ydoc.transact(() => {
        errorsMap.set('jobs', {
          'job-123': { name: ['Job name is too long'] },
        });
      });

      // Verify errors are present
      let state = store.getSnapshot();
      let job = state.jobs.find(j => j.id === 'job-123');
      expect(job?.errors).toEqual({ name: ['Job name is too long'] });

      // Update the job name in Y.Doc (simulating collaborative edit)
      const jobsArray = ydoc.getArray('jobs');
      const jobMap = jobsArray.get(0) as Y.Map<unknown>;

      ydoc.transact(() => {
        jobMap.set('name', 'Updated Job Name');
      });

      // Verify errors are still preserved after Y.Doc update
      state = store.getSnapshot();
      job = state.jobs.find(j => j.id === 'job-123');
      expect(job?.name).toBe('Updated Job Name');
      expect(job?.errors).toEqual({ name: ['Job name is too long'] });
    });

    it('should preserve edge errors when edges array is updated', () => {
      const errorsMap = ydoc.getMap('errors');

      // Set edge errors
      ydoc.transact(() => {
        errorsMap.set('edges', {
          'edge-abc': { condition_expression: ["can't be blank"] },
        });
      });

      // Verify errors are present
      let state = store.getSnapshot();
      let edge = state.edges.find(e => e.id === 'edge-abc');
      expect(edge?.errors).toEqual({
        condition_expression: ["can't be blank"],
      });

      // Update the edge condition_type in Y.Doc (simulating collaborative edit)
      const edgesArray = ydoc.getArray('edges');
      const edgeMap = edgesArray.get(0) as Y.Map<unknown>;

      ydoc.transact(() => {
        edgeMap.set('condition_type', 'always');
      });

      // Verify errors are still preserved after Y.Doc update
      state = store.getSnapshot();
      edge = state.edges.find(e => e.id === 'edge-abc');
      expect(edge?.condition_type).toBe('always');
      expect(edge?.errors).toEqual({
        condition_expression: ["can't be blank"],
      });
    });

    it('should preserve trigger errors when triggers array is updated', () => {
      const errorsMap = ydoc.getMap('errors');

      // Set trigger errors
      ydoc.transact(() => {
        errorsMap.set('triggers', {
          'trigger-789': { cron_expression: ['Invalid cron expression'] },
        });
      });

      // Verify errors are present
      let state = store.getSnapshot();
      let trigger = state.triggers.find(t => t.id === 'trigger-789');
      expect(trigger?.errors).toEqual({
        cron_expression: ['Invalid cron expression'],
      });

      // Update the trigger cron_expression in Y.Doc (simulating collaborative edit)
      const triggersArray = ydoc.getArray('triggers');
      const triggerMap = triggersArray.get(0) as Y.Map<unknown>;

      ydoc.transact(() => {
        triggerMap.set('cron_expression', '0 0 * * *');
      });

      // Verify errors are still preserved after Y.Doc update
      state = store.getSnapshot();
      trigger = state.triggers.find(t => t.id === 'trigger-789');
      expect(trigger?.cron_expression).toBe('0 0 * * *');
      expect(trigger?.errors).toEqual({
        cron_expression: ['Invalid cron expression'],
      });
    });

    it('should clear preserved errors when errors are removed from Y.Doc', () => {
      const errorsMap = ydoc.getMap('errors');

      // Set job errors
      ydoc.transact(() => {
        errorsMap.set('jobs', {
          'job-123': { name: ['Job name is too long'] },
        });
      });

      // Verify errors are present
      let state = store.getSnapshot();
      let job = state.jobs.find(j => j.id === 'job-123');
      expect(job?.errors).toEqual({ name: ['Job name is too long'] });

      // Clear errors
      ydoc.transact(() => {
        errorsMap.set('jobs', {});
      });

      // Verify errors are cleared
      state = store.getSnapshot();
      job = state.jobs.find(j => j.id === 'job-123');
      expect(job?.errors).toEqual({});
    });
  });
});
