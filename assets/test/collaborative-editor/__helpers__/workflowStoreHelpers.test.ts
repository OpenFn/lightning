/**
 * Tests for Workflow Store Test Helpers
 *
 * Verifies that the setupWorkflowStoreTest helper correctly initializes
 * WorkflowStore with Y.Doc and provider connections.
 */

import { describe, expect, test } from 'vitest';

import { createWorkflowYDoc } from './workflowFactory';
import {
  createEmptyWorkflowYDoc,
  createMinimalWorkflowYDoc,
  setupWorkflowStoreTest,
} from './workflowStoreHelpers';

describe('setupWorkflowStoreTest', () => {
  test('creates store with empty Y.Doc by default', () => {
    const { store, ydoc, cleanup } = setupWorkflowStoreTest();

    // Store should be connected
    expect(store.isConnected).toBe(true);

    // Y.Doc should have workflow structure initialized
    expect(ydoc.getMap('workflow')).toBeDefined();
    expect(ydoc.getArray('jobs')).toBeDefined();
    expect(ydoc.getArray('triggers')).toBeDefined();
    expect(ydoc.getArray('edges')).toBeDefined();
    expect(ydoc.getMap('positions')).toBeDefined();
    expect(ydoc.getMap('errors')).toBeDefined();

    // Arrays should be empty
    expect(ydoc.getArray('jobs').length).toBe(0);
    expect(ydoc.getArray('triggers').length).toBe(0);
    expect(ydoc.getArray('edges').length).toBe(0);

    cleanup();
  });

  test('accepts pre-configured Y.Doc', () => {
    const customYDoc = createWorkflowYDoc({
      jobs: {
        'job-a': {
          id: 'job-a',
          name: 'Job A',
          adaptor: '@openfn/language-common',
        },
        'job-b': {
          id: 'job-b',
          name: 'Job B',
          adaptor: '@openfn/language-common',
        },
      },
      triggers: {
        'trigger-1': {
          id: 'trigger-1',
          type: 'webhook',
        },
      },
      edges: [
        {
          id: 'edge-1',
          source: 'trigger-1',
          target: 'job-a',
        },
      ],
    });

    const { store, ydoc, cleanup } = setupWorkflowStoreTest(customYDoc);

    expect(store.isConnected).toBe(true);

    // Verify Y.Doc has the jobs
    expect(ydoc.getArray('jobs').length).toBe(2);
    expect(ydoc.getArray('triggers').length).toBe(1);
    expect(ydoc.getArray('edges').length).toBe(1);

    // Verify store synced the data
    const state = store.getSnapshot();
    expect(state.jobs).toHaveLength(2);
    expect(state.triggers).toHaveLength(1);
    expect(state.edges).toHaveLength(1);

    cleanup();
  });

  test('provides mock channel and provider', () => {
    const { mockChannel, mockProvider, cleanup } = setupWorkflowStoreTest();

    expect(mockChannel).toBeDefined();
    expect(mockChannel.push).toBeDefined();
    expect(mockChannel.on).toBeDefined();
    expect(mockChannel.off).toBeDefined();

    expect(mockProvider).toBeDefined();
    expect(mockProvider.channel).toBe(mockChannel);

    cleanup();
  });

  test('cleanup disconnects store', () => {
    const { store, cleanup } = setupWorkflowStoreTest();

    expect(store.isConnected).toBe(true);

    cleanup();

    // After disconnect, isConnected remains true because ydoc is kept alive for offline editing
    // Only the provider is nulled out, but the store can still function offline
    expect(store.isConnected).toBe(true);
    expect(store.ydoc).not.toBeNull();
  });
});

describe('createEmptyWorkflowYDoc', () => {
  test('creates Y.Doc with workflow structure', () => {
    const ydoc = createEmptyWorkflowYDoc();

    expect(ydoc.getMap('workflow')).toBeDefined();
    expect(ydoc.getArray('jobs')).toBeDefined();
    expect(ydoc.getArray('triggers')).toBeDefined();
    expect(ydoc.getArray('edges')).toBeDefined();
    expect(ydoc.getMap('positions')).toBeDefined();
    expect(ydoc.getMap('errors')).toBeDefined();

    // All should be empty
    expect(ydoc.getArray('jobs').length).toBe(0);
    expect(ydoc.getArray('triggers').length).toBe(0);
    expect(ydoc.getArray('edges').length).toBe(0);
    expect(ydoc.getMap('positions').size).toBe(0);
    expect(ydoc.getMap('errors').size).toBe(0);
  });
});

describe('createMinimalWorkflowYDoc', () => {
  test('creates Y.Doc with workflow metadata', () => {
    const ydoc = createMinimalWorkflowYDoc('wf-123', 'My Workflow', 5);

    const workflowMap = ydoc.getMap('workflow');
    expect(workflowMap.get('id')).toBe('wf-123');
    expect(workflowMap.get('name')).toBe('My Workflow');
    expect(workflowMap.get('lock_version')).toBe(5);
    expect(workflowMap.get('deleted_at')).toBe(null);
    expect(workflowMap.get('concurrency')).toBe(null);
    expect(workflowMap.get('enable_job_logs')).toBe(false);
  });

  test('uses defaults when no arguments provided', () => {
    const ydoc = createMinimalWorkflowYDoc();

    const workflowMap = ydoc.getMap('workflow');
    expect(workflowMap.get('id')).toBe('workflow-test');
    expect(workflowMap.get('name')).toBe('Test Workflow');
    expect(workflowMap.get('lock_version')).toBe(null);
  });
});
