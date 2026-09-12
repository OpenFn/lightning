/**
 * Tests for `selectCanEditContent`, the answer to "may this person change the
 * workflow's content right now?".
 *
 * Two independent facts, and neither implies the other. The role says whether
 * they may edit at all; the lifecycle lock says whether the content may change.
 * They used to arrive merged into `can_edit_workflow`, which meant a viewer and
 * an editor on a live workflow were told the same thing and the client had to
 * guess which it meant.
 *
 * Splitting them left every caller having to remember to ask twice. This is
 * what `StoreProvider` hands the workflow store as its write gate, so getting
 * it wrong lets writes into the local document that the server then refuses,
 * showing the user edits that will never persist.
 */

import { describe, expect, test } from 'vitest';

import { selectCanEditContent } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import type { SessionContextState } from '../../../js/collaborative-editor/types/sessionContext';

const state = (
  canEdit: boolean | null,
  contentLocked: boolean
): SessionContextState =>
  ({
    permissions:
      canEdit === null
        ? null
        : {
            can_edit_workflow: canEdit,
            can_run_workflow: true,
            can_write_webhook_auth_method: true,
            can_provision_sandbox: true,
            can_archive_sandbox: true,
          },
    contentLocked,
  }) as SessionContextState;

describe('selectCanEditContent', () => {
  test('an editor on an unlocked workflow may edit', () => {
    expect(selectCanEditContent(state(true, false))).toBe(true);
  });

  test('an editor on a live workflow may not', () => {
    // The role says yes and only the lifecycle says no, which is exactly the
    // case that reading the role alone gets wrong.
    expect(selectCanEditContent(state(true, true))).toBe(false);
  });

  test('a viewer may not, locked or not', () => {
    expect(selectCanEditContent(state(false, false))).toBe(false);
    expect(selectCanEditContent(state(false, true))).toBe(false);
  });

  test('permissions not loaded yet reads as no', () => {
    // Before the session context arrives, the safe answer is no: opening the
    // gate first and closing it later would let through the writes made in
    // between.
    expect(selectCanEditContent(state(null, false))).toBe(false);
  });
});
