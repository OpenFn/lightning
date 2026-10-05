import type * as Y from 'yjs';

import type { Session } from '../types/session';

/**
 * Reconcile dangling references in the Y.Doc. Currently: null any cron trigger
 * `cron_cursor_job_id` that points at a job no longer present in the jobs array.
 *
 * ADVISORY ONLY. This is a client-side UX fast-path so a structural mutation that
 * orphans a cron cursor does not leave the editor in a state that fails server
 * validation on save. It is NOT the correctness guarantee — the server-side
 * compound foreign key (`ON DELETE SET NULL (cron_cursor_job_id)`) and the
 * `Workflows.save_workflow/3` rescue are. In particular it CANNOT close the
 * concurrent-editor race: if User A deletes Job B and User B saves before A's
 * deletion has merged into B's doc, B's `cron_cursor_job_id` is still live in B's
 * view and this function leaves it alone. The server resolves that case
 * authoritatively.
 *
 * This is the single client-side home for dangling-reference reconciliation. Any
 * new structural mutation that can orphan a reference (e.g. a future bulk
 * job-removal or trigger-removal command) MUST call this function rather than
 * re-implementing per-path cleanup.
 *
 * Pattern 1 (Y.Doc → observer → Immer → notify): callers rely on the existing
 * observeDeep handlers to propagate the nulled cursor to React. No notify() here.
 *
 * @param ydoc the workflow document
 * @param options.inTransaction true when called from within an already-open
 *   `ydoc.transact` (e.g. `removeJob`, `applyToYDoc`); avoids nesting a second
 *   transaction, which Yjs forbids. When omitted/false the function opens its own
 *   transaction.
 */
export function reconcileDanglingReferences(
  ydoc: Session.WorkflowDoc,
  options: { inTransaction?: boolean } = {}
): void {
  const jobsArray = ydoc.getArray('jobs');
  const triggersArray = ydoc.getArray('triggers');

  // Reads first (outside the write closure) so the transaction body does only
  // writes — mirrors removeJob's read-then-transact shape.
  const jobs = jobsArray.toArray() as Y.Map<unknown>[];
  const triggers = triggersArray.toArray() as Y.Map<unknown>[];

  const jobIds = new Set(jobs.map(job => job.get('id') as string));

  const danglingTriggers = triggers.filter(trigger => {
    const cursor = trigger.get('cron_cursor_job_id');
    return typeof cursor === 'string' && !jobIds.has(cursor);
  });

  // Early-return when nothing dangles so we never emit an empty transaction on
  // every save.
  if (danglingTriggers.length === 0) return;

  const apply = () => {
    danglingTriggers.forEach(trigger => {
      trigger.set('cron_cursor_job_id', null);
    });
  };

  if (options.inTransaction) {
    apply();
  } else {
    ydoc.transact(apply);
  }
}
