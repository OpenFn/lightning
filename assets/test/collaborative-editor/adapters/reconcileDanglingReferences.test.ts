/**
 * Tests for reconcileDanglingReferences
 *
 * The single advisory client-side owner of dangling-reference cleanup. These
 * exercise the contract directly on a bare Y.Doc: null a cron cursor that points
 * at a missing job, leave valid/null cursors alone, no-op (no transaction) when
 * nothing dangles, and apply without nesting when called inside an open
 * transaction.
 */

import { describe, test, expect, beforeEach } from 'vitest';
import * as Y from 'yjs';

import { reconcileDanglingReferences } from '../../../js/collaborative-editor/adapters/reconcileDanglingReferences';
import type { Session } from '../../../js/collaborative-editor/types/session';

const addJob = (ydoc: Session.WorkflowDoc, id: string) => {
  const job = new Y.Map();
  job.set('id', id);
  (ydoc.getArray('jobs') as Y.Array<Y.Map<unknown>>).push([job]);
};

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

describe('reconcileDanglingReferences', () => {
  let ydoc: Session.WorkflowDoc;

  beforeEach(() => {
    ydoc = new Y.Doc() as Session.WorkflowDoc;
  });

  test('nulls a cron cursor pointing at a job not in the jobs set', () => {
    addJob(ydoc, 'job-a');
    addCronTrigger(ydoc, 'trigger-1', 'job-ghost');

    reconcileDanglingReferences(ydoc);

    expect(cursorOf(ydoc, 0)).toBeNull();
  });

  test('leaves a valid cron cursor untouched', () => {
    addJob(ydoc, 'job-a');
    addCronTrigger(ydoc, 'trigger-1', 'job-a');

    reconcileDanglingReferences(ydoc);

    expect(cursorOf(ydoc, 0)).toBe('job-a');
  });

  test('leaves a null cron cursor untouched', () => {
    addJob(ydoc, 'job-a');
    addCronTrigger(ydoc, 'trigger-1', null);

    reconcileDanglingReferences(ydoc);

    expect(cursorOf(ydoc, 0)).toBeNull();
  });

  test('nulls dangling cursors across multiple triggers, sparing valid ones', () => {
    addJob(ydoc, 'job-a');
    addCronTrigger(ydoc, 'trigger-1', 'job-ghost');
    addCronTrigger(ydoc, 'trigger-2', 'job-a');
    addCronTrigger(ydoc, 'trigger-3', 'job-gone');

    reconcileDanglingReferences(ydoc);

    expect(cursorOf(ydoc, 0)).toBeNull();
    expect(cursorOf(ydoc, 1)).toBe('job-a');
    expect(cursorOf(ydoc, 2)).toBeNull();
  });

  test('emits no transaction when nothing dangles', () => {
    addJob(ydoc, 'job-a');
    addCronTrigger(ydoc, 'trigger-1', 'job-a');

    let updates = 0;
    const onUpdate = () => {
      updates += 1;
    };
    ydoc.on('update', onUpdate);

    reconcileDanglingReferences(ydoc);

    ydoc.off('update', onUpdate);
    expect(updates).toBe(0);
  });

  test('applies without nesting when called inside an open transaction', () => {
    addJob(ydoc, 'job-a');
    addCronTrigger(ydoc, 'trigger-1', 'job-ghost');

    let updates = 0;
    const onUpdate = () => {
      updates += 1;
    };
    ydoc.on('update', onUpdate);

    // Calling inside an already-open transaction must not throw
    // "Transaction already in progress" and must coalesce into the one update.
    expect(() => {
      ydoc.transact(() => {
        reconcileDanglingReferences(ydoc, { inTransaction: true });
      });
    }).not.toThrow();

    ydoc.off('update', onUpdate);
    expect(cursorOf(ydoc, 0)).toBeNull();
    expect(updates).toBe(1);
  });
});
