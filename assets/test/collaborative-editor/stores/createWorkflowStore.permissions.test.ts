/**
 * WorkflowStore edit-permission enforcement
 *
 * The workflow store's structural write mutators (add/update/remove of jobs,
 * edges, triggers, and positions, plus workflow-field updates) must not change
 * the shared Y.Doc when the current user only has view access. Whether the
 * user may edit is supplied by the `getCanEdit` getter passed to
 * `createWorkflowStore`.
 *
 * These tests verify that when `getCanEdit()` returns false the mutators
 * return early, leaving both the Y.Doc and the store snapshot untouched, and
 * that they apply normally when it returns true.
 *
 * The collaboration channel enforces the same rule on the server; blocking the
 * writes here as well means a view-only user cannot emit them even by, for
 * example, removing a `disabled` attribute in the DOM or dragging a node.
 */

import { describe, test, expect, beforeEach, vi } from 'vitest';
import * as Y from 'yjs';
import type { Channel } from 'phoenix';
import type { PhoenixChannelProvider } from 'y-phoenix-channel';

import { createWorkflowStore } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import type { WorkflowStoreInstance } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Session } from '../../../js/collaborative-editor/types/session';

describe('WorkflowStore - edit-permission enforcement', () => {
  let ydoc: Session.WorkflowDoc;
  let mockProvider: PhoenixChannelProvider & { channel: Channel };
  // Mutable flag read lazily by the store's getCanEdit getter.
  let canEdit: boolean;

  const buildStore = (): WorkflowStoreInstance => {
    const store = createWorkflowStore({ getCanEdit: () => canEdit });
    store.connect(ydoc, mockProvider);
    return store;
  };

  beforeEach(() => {
    canEdit = true;
    ydoc = new Y.Doc() as Session.WorkflowDoc;

    const mockChannel = {
      push: vi.fn(),
      on: vi.fn(),
      off: vi.fn(),
    } as unknown as Channel;

    mockProvider = {
      channel: mockChannel,
      synced: true,
      awareness: null,
      doc: ydoc,
    } as unknown as PhoenixChannelProvider & { channel: Channel };

    // Seed a minimal workflow with one job so update/position paths have a target.
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('id', 'workflow-123');
    workflowMap.set('name', 'Original Name');
    workflowMap.set('lock_version', null);

    const jobsArray = ydoc.getArray('jobs');
    const jobMap = new Y.Map();
    jobMap.set('id', 'job-1');
    jobMap.set('name', 'Original Job');
    jobMap.set('body', new Y.Text('// original'));
    jobMap.set('adaptor', '@openfn/language-common@latest');
    jobsArray.push([jobMap]);

    ydoc.getArray('triggers');
    ydoc.getArray('edges');
    ydoc.getMap('positions');
    ydoc.getMap('errors');
  });

  describe('when getCanEdit() returns false (read-only viewer)', () => {
    let store: WorkflowStoreInstance;

    beforeEach(() => {
      canEdit = false;
      store = buildStore();
    });

    test('structural write mutators no-op, leaving Y.Doc and snapshot unchanged', () => {
      const before = store.getSnapshot();

      store.updateWorkflow({ name: 'Hacked Name' });
      store.updateJob('job-1', { name: 'Hacked Job' });
      store.updatePosition('job-1', { x: 999, y: 999 });
      store.updatePositions({ 'job-1': { x: 111, y: 222 } });
      store.addJob({ id: 'job-2', name: 'Sneaky Job' });
      store.addEdge({
        id: 'edge-1',
        source_job_id: 'job-1',
        target_job_id: 'job-2',
      });
      store.updateTrigger('trigger-1', { enabled: true });
      store.setEnabled(true);

      const after = store.getSnapshot();

      // Snapshot is referentially unchanged (no notify fired).
      expect(after).toBe(before);
      expect(after.workflow?.name).toBe('Original Name');
      expect(after.jobs).toHaveLength(1);
      expect(after.jobs[0]?.name).toBe('Original Job');

      // Y.Doc itself is untouched.
      expect(ydoc.getMap('workflow').get('name')).toBe('Original Name');
      expect(ydoc.getArray('jobs').length).toBe(1);
      expect(ydoc.getArray('edges').length).toBe(0);
      expect(ydoc.getMap('positions').toJSON()).toEqual({});
    });

    test('removeJob and removeEdge no-op', () => {
      store.removeJob('job-1');
      expect(store.getSnapshot().jobs).toHaveLength(1);
      expect(ydoc.getArray('jobs').length).toBe(1);
    });
  });

  describe('when getCanEdit() returns true (editor)', () => {
    let store: WorkflowStoreInstance;

    beforeEach(() => {
      canEdit = true;
      store = buildStore();
    });

    test('structural write mutators apply to Y.Doc and snapshot', () => {
      store.updateWorkflow({ name: 'Edited Name' });
      store.updateJob('job-1', { name: 'Edited Job' });
      store.updatePosition('job-1', { x: 10, y: 20 });
      store.updatePositions({ 'job-1': { x: 30, y: 40 } });

      const after = store.getSnapshot();
      expect(after.workflow?.name).toBe('Edited Name');
      expect(after.jobs[0]?.name).toBe('Edited Job');
      expect(after.positions['job-1']).toEqual({ x: 30, y: 40 });

      expect(ydoc.getMap('workflow').get('name')).toBe('Edited Name');
      expect(ydoc.getMap('positions').get('job-1')).toEqual({ x: 30, y: 40 });
    });
  });

  test('permission is read lazily: flipping from false to true unblocks writes', () => {
    canEdit = false;
    const store = buildStore();

    store.updateWorkflow({ name: 'Blocked' });
    expect(store.getSnapshot().workflow?.name).toBe('Original Name');

    // Permission granted later (e.g. session context updates).
    canEdit = true;
    store.updateWorkflow({ name: 'Allowed' });
    expect(store.getSnapshot().workflow?.name).toBe('Allowed');
  });
});
