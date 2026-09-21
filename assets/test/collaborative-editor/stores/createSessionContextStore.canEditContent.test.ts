
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
    expect(selectCanEditContent(state(true, true))).toBe(false);
  });

  test('a viewer may not, locked or not', () => {
    expect(selectCanEditContent(state(false, false))).toBe(false);
    expect(selectCanEditContent(state(false, true))).toBe(false);
  });

  test('permissions not loaded yet reads as no', () => {
    expect(selectCanEditContent(state(null, false))).toBe(false);
  });
});
