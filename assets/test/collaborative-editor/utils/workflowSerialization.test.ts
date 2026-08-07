import { describe, it, expect } from 'vitest';

import {
  prepareWorkflowForSerialization,
  serializeWorkflowToYAML,
} from '../../../js/collaborative-editor/utils/workflowSerialization';

describe('workflowSerialization', () => {
  describe('serializeWorkflowToYAML', () => {
    it('serializes the workflow to v2 portability YAML', () => {
      const workflow = {
        id: 'workflow-uuid-123',
        name: 'Test Workflow',
        jobs: [
          {
            id: 'job-uuid-456',
            name: 'Get Data',
            adaptor: '@openfn/language-http@latest',
            body: 'fn(state => state);',
          },
        ],
        triggers: [
          {
            id: 'trigger-uuid-789',
            type: 'webhook' as const,
            enabled: true,
          },
        ],
        edges: [
          {
            id: 'edge-uuid-abc',
            condition_type: 'always',
            enabled: true,
            target_job_id: 'job-uuid-456',
            source_trigger_id: 'trigger-uuid-789',
          },
        ],
        positions: {
          'job-uuid-456': { x: 100, y: 200 },
          'trigger-uuid-789': { x: 100, y: 50 },
        },
      };

      const yaml = serializeWorkflowToYAML(workflow);

      expect(yaml).toBeDefined();
      // v2 wire shape: top-level `name`, unified `steps:` array, trigger
      // discriminator under `type:`, job code under `expression:`.
      expect(yaml).toContain('name: Test Workflow');
      expect(yaml).toContain('steps:');
      expect(yaml).toContain('type: webhook');
      expect(yaml).toContain('expression:');
      // v2 is stateless — UUIDs do not appear on the wire; steps reference
      // each other by hyphenated step id (derived from name).
      expect(yaml).not.toContain('workflow-uuid-123');
      expect(yaml).not.toContain('job-uuid-456');
      expect(yaml).not.toContain('trigger-uuid-789');
    });

    it('preserves all job properties', () => {
      const workflow = {
        id: 'wf-1',
        name: 'Test',
        jobs: [
          {
            id: 'job-1',
            name: 'My Job',
            adaptor: '@openfn/language-common@latest',
            body: 'console.log("hello");',
          },
        ],
        triggers: [{ id: 'trig-1', type: 'webhook' as const, enabled: true }],
        edges: [
          {
            id: 'edge-1',
            condition_type: 'always',
            enabled: true,
            target_job_id: 'job-1',
            source_trigger_id: 'trig-1',
          },
        ],
        positions: null,
      };

      const yaml = serializeWorkflowToYAML(workflow);

      expect(yaml).toContain('name: My Job');
      expect(yaml).toContain('@openfn/language-common@latest');
      expect(yaml).toContain('console.log("hello");');
    });
  });

  describe('prepareWorkflowForSerialization', () => {
    it('returns null when workflow is null', () => {
      const result = prepareWorkflowForSerialization(null, [], [], [], {});
      expect(result).toBeNull();
    });

    it('returns null when jobs array is empty', () => {
      const result = prepareWorkflowForSerialization(
        { id: 'wf-1', name: 'Test' },
        [],
        [],
        [],
        {}
      );
      expect(result).toBeNull();
    });

    it('transforms store state to serializable format', () => {
      const workflow = { id: 'wf-1', name: 'Test Workflow' };
      const jobs = [
        { id: 'job-1', name: 'Job One', adaptor: '@openfn/http', body: 'code' },
      ];
      const triggers = [{ id: 'trig-1', type: 'webhook', enabled: true }];
      const edges = [
        {
          id: 'edge-1',
          condition_type: 'always',
          enabled: true,
          target_job_id: 'job-1',
          source_trigger_id: 'trig-1',
        },
      ];
      const positions = { 'job-1': { x: 0, y: 0 } };

      const result = prepareWorkflowForSerialization(
        workflow,
        jobs,
        triggers,
        edges,
        positions
      );

      expect(result).not.toBeNull();
      expect(result?.id).toBe('wf-1');
      expect(result?.name).toBe('Test Workflow');
      expect(result?.jobs).toHaveLength(1);
      expect(result?.jobs[0].id).toBe('job-1');
    });
  });
});
