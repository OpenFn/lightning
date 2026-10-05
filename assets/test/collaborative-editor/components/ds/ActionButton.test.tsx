/**
 * ActionButton - the new design system's primary action button.
 *
 * Only the `loading` implies-disabled rule carries logic; everything else is
 * styling, which is deliberately not asserted here. Class-name assertions break
 * on every Tailwind tweak without catching real regressions.
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test, vi } from 'vitest';

import { ActionButton } from '#/collaborative-editor/components/ds/ActionButton';

describe('ActionButton', () => {
  test('loading disables the button and suppresses clicks', async () => {
    const user = userEvent.setup();
    const onClick = vi.fn();
    render(
      <ActionButton loading onClick={onClick}>
        Create
      </ActionButton>
    );

    const button = screen.getByRole('button', { name: 'Create' });
    expect(button).toBeDisabled();

    await user.click(button);
    expect(onClick).not.toHaveBeenCalled();
  });

  test('renders and clicks normally when idle', async () => {
    const user = userEvent.setup();
    const onClick = vi.fn();
    render(<ActionButton onClick={onClick}>Create</ActionButton>);

    const button = screen.getByRole('button', { name: 'Create' });
    expect(button).toBeEnabled();

    await user.click(button);
    expect(onClick).toHaveBeenCalledOnce();
  });
});
