/**
 * RestoreVersionDialog Tests
 *
 * Restoring is a deliberate rollback, not a mistake to be talked out of, so the
 * dialog's job is to say what it costs. The cost that matters is the one nobody
 * should discover afterwards: a trigger added since that version disappears and
 * the URL built from it stops answering.
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { RestoreVersionDialog } from '../../../js/collaborative-editor/components/RestoreVersionDialog';
import type { LosingTrigger } from '../../../js/collaborative-editor/components/RestoreVersionDialog';
import { KeyboardProvider } from '../../../js/collaborative-editor/keyboard';

const onConfirm = vi.fn<() => Promise<boolean>>();
const onCancel = vi.fn();

function renderDialog(losingTriggers: LosingTrigger[] | null, isOpen = true) {
  return render(
    <KeyboardProvider>
      <RestoreVersionDialog
        isOpen={isOpen}
        versionNumber={3}
        losingTriggers={losingTriggers}
        onConfirm={onConfirm}
        onCancel={onCancel}
      />
    </KeyboardProvider>
  );
}

// This branch's Button does not forward data-* attributes yet (that is #4991),
// so the confirm button is found by its accessible name.
const confirmButton = () =>
  screen.getByRole('button', { name: /^Restor(e|ing)/ });

const webhook: LosingTrigger = {
  id: 'trigger-1',
  type: 'webhook',
  custom_path: 'orders-in',
  enabled: true,
};

const cron: LosingTrigger = {
  id: 'trigger-2',
  type: 'cron',
  custom_path: null,
  enabled: false,
};

describe('RestoreVersionDialog', () => {
  beforeEach(() => {
    onConfirm.mockReset();
    onConfirm.mockResolvedValue(true);
    onCancel.mockReset();
  });

  test('names the version being restored', () => {
    renderDialog([]);

    expect(screen.getByTestId('restore-version-dialog')).toHaveTextContent(
      'Restore v3?'
    );
  });

  test('will not let you confirm until the check has answered', () => {
    renderDialog(null);

    expect(screen.getByTestId('restore-checking')).toBeInTheDocument();
    expect(confirmButton()).toBeDisabled();
  });

  test('names each trigger it will delete, and its URL', async () => {
    renderDialog([webhook, cron]);

    const warning = await screen.findByTestId('restore-losing-triggers');

    expect(warning).toHaveTextContent('2 triggers will be deleted');
    expect(warning).toHaveTextContent('the webhook at /orders-in');
    expect(warning).toHaveTextContent('which is on now');
    expect(warning).toHaveTextContent('a scheduled trigger');
  });

  test('says nothing about triggers when none are lost', () => {
    renderDialog([]);

    expect(
      screen.queryByTestId('restore-losing-triggers')
    ).not.toBeInTheDocument();
    expect(confirmButton()).toBeEnabled();
  });

  test('confirming restores', async () => {
    const user = userEvent.setup();
    renderDialog([]);

    await user.click(confirmButton());

    await waitFor(() => {
      expect(onConfirm).toHaveBeenCalledTimes(1);
    });
  });

  test('a failed restore leaves the dialog usable', async () => {
    onConfirm.mockResolvedValue(false);
    const user = userEvent.setup();
    renderDialog([]);

    await user.click(confirmButton());

    await waitFor(() => {
      expect(confirmButton()).toBeEnabled();
    });
  });

  test('cancelling restores nothing', async () => {
    const user = userEvent.setup();
    renderDialog([]);

    await user.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(onCancel).toHaveBeenCalled();
    expect(onConfirm).not.toHaveBeenCalled();
  });
});
