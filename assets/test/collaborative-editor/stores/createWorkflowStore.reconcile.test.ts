/**
 * WorkflowStore - Save path must not reconcile dangling references
 *
 * Regression guard for the CRDT read/write asymmetry described in
 * collab-session-resilience finding 07 #2 (PR #4816).
 *
 * The save path (`saveWorkflow` / `saveAndSyncWorkflow`) must be a pure read of
 * the converged Y.Doc. It must NOT run reconcileDanglingReferences, because on a
 * stale local replica that would null a cron cursor that is legitimately valid
 * in the converged doc and broadcast that null to every collaborator — silent,
 * non-undoable data loss triggered by a save.
 *
 * The race is reproduced single-replica by constructing a Y.Doc whose cron
 * trigger `cron_cursor_job_id` points at a job ID absent from the local jobs
 * array — exactly what a replica that has not yet merged a collaborator's
 * "add job" op looks like. The cursor must survive the save untouched.
 *
 * Dangling-reference cleanup on the mutator paths (removeJob, applyToYDoc)
 * remains correct and is covered by the adapter test and removeJob cases.
 */

import { describe, test, expect, beforeEach, afterEach } from 'vitest';
import * as Y from 'yjs';

import type { WorkflowStoreInstance } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Session } from '../../../js/collaborative-editor/types/session';
import {
  createMockChannelPushOk,
  type MockPhoenixChannel,
} from '../__helpers__/channelMocks';
import {
  setupWorkflowStoreTest,
  createMinimalWorkflowYDoc,
} from '../__helpers__';

const addCronTrigger = (
  ydoc: Session.WorkflowDoc,
  id: string,
  cursor: string | null
) => {
  const trigger = new Y.Map();
  trigger.set('id', id);
  trigger.set('type', 'cron');
  trigger.set('cron_cursor_job_id', cursor);
  (ydoc.getArray('triggers') as Y.Array<Y.Map<unknown>>).push([trigger]);
};

const cursorOf = (ydoc: Session.WorkflowDoc, index: number) =>
  (ydoc.getArray('triggers').get(index) as Y.Map<unknown>).get(
    'cron_cursor_job_id'
  );

describe('WorkflowStore - Save path does not reconcile dangling references', () => {
  let store: WorkflowStoreInstance;
  let ydoc: Session.WorkflowDoc;
  let mockChannel: MockPhoenixChannel;
  let cleanup: () => void;

  beforeEach(() => {
    ({ store, ydoc, mockChannel, cleanup } = setupWorkflowStoreTest(
      createMinimalWorkflowYDoc('workflow-123')
    ));

    // Configure push to resolve save calls with a successful ok response.
    mockChannel.push = createMockChannelPushOk({
      saved_at: new Date().toISOString(),
      lock_version: 1,
    });

    // The one genuinely test-specific bit: a cron cursor pointing at a job
    // absent from this replica's jobs array (simulates a not-yet-merged
    // collaborator "add job" op).
    addCronTrigger(ydoc, 'trigger-1', 'job-added-by-collaborator');
  });

  afterEach(() => {
    cleanup();
  });

  test.each([
    [
      'saveWorkflow',
      'save_workflow',
      (s: WorkflowStoreInstance) => s.saveWorkflow(),
    ],
    [
      'saveAndSyncWorkflow',
      'save_and_sync',
      (s: WorkflowStoreInstance) => s.saveAndSyncWorkflow('commit message'),
    ],
  ] as const)(
    '%s leaves a cursor that is dangling only in the local view untouched',
    async (_name, pushEvent, save) => {
      let updates = 0;
      const onUpdate = () => {
        updates += 1;
      };
      ydoc.on('update', onUpdate);

      await save(store);

      ydoc.off('update', onUpdate);

      // No null broadcast: cursor unchanged, no Y.Doc write emitted by the save path.
      expect(cursorOf(ydoc, 0)).toBe('job-added-by-collaborator');
      expect(updates).toBe(0);

      // The (stale) cursor is forwarded to the server, which reconciles authoritatively.
      expect(mockChannel.push).toHaveBeenCalledWith(
        pushEvent,
        expect.objectContaining({
          triggers: [
            expect.objectContaining({
              id: 'trigger-1',
              cron_cursor_job_id: 'job-added-by-collaborator',
            }),
          ],
        })
      );
    }
  );
});
