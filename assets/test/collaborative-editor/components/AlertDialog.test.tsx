// Tests for the shared confirmation dialog: confirm/cancel wiring and the
// MODAL-priority Escape handler that closes it inside the editor.

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { ReactElement } from 'react';
import { describe, expect, test, vi } from 'vitest';

import { AlertDialog } from '../../../js/collaborative-editor/components/AlertDialog';
import { KeyboardProvider } from '../../../js/collaborative-editor/keyboard';

// AlertDialog registers a MODAL-priority Escape handler, so it must render
// inside a KeyboardProvider (useKeyboardShortcut throws otherwise).
const renderDialog = (ui: ReactElement) =>
  render(ui, { wrapper: KeyboardProvider });

const baseProps = {
  isOpen: true,
  title: 'Switch to draft',
  description: 'This takes the workflow offline.',
  confirmLabel: 'Switch to draft',
};

describe('AlertDialog', () => {
  test('confirm fires onConfirm and onClose', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    const onConfirm = vi.fn();

    renderDialog(
      <AlertDialog {...baseProps} onClose={onClose} onConfirm={onConfirm} />
    );

    await user.click(screen.getByRole('button', { name: 'Switch to draft' }));

    expect(onConfirm).toHaveBeenCalledTimes(1);
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  test('cancel closes without confirming', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    const onConfirm = vi.fn();

    renderDialog(
      <AlertDialog {...baseProps} onClose={onClose} onConfirm={onConfirm} />
    );

    await user.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(onConfirm).not.toHaveBeenCalled();
  });

  test('pressing Escape closes the dialog without confirming', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    const onConfirm = vi.fn();

    renderDialog(
      <AlertDialog {...baseProps} onClose={onClose} onConfirm={onConfirm} />
    );

    // The MODAL-priority handler runs ahead of the IDE/inspector handlers, so
    // Escape reaches the dialog. In isolation Headless UI's own default also
    // fires (no IDE handler suppresses it here), so we assert the dialog closed
    // rather than a precise call count. It only cancels: confirm never runs.
    await user.keyboard('{Escape}');

    expect(onClose).toHaveBeenCalled();
    expect(onConfirm).not.toHaveBeenCalled();
  });

  test('does not register an Escape handler while closed', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();

    renderDialog(
      <AlertDialog
        {...baseProps}
        isOpen={false}
        onClose={onClose}
        onConfirm={vi.fn()}
      />
    );

    await user.keyboard('{Escape}');

    expect(onClose).not.toHaveBeenCalled();
  });
});
