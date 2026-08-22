import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test, vi } from 'vitest';

import { PickerButton } from '#/picker/PickerButton';

const projectDefaults = {
  'data-icon': 'hero-folder',
  'data-accent-icon': 'hero-beaker',
  'data-open-event': 'open-project-picker',
};

describe('PickerButton plain mode', () => {
  test('renders the plain label', () => {
    render(<PickerButton {...projectDefaults} data-label="ethiopia" />);
    expect(
      screen.getByRole('button', { name: /ethiopia/ })
    ).toBeInTheDocument();
  });

  test('does not apply background color styling without is-sandbox', () => {
    render(
      <PickerButton
        {...projectDefaults}
        data-label="ethiopia"
        data-color="#abcdef"
      />
    );
    const button = screen.getByRole('button');
    expect(button.style.backgroundColor).toBe('');
  });
});

describe('PickerButton sandbox mode', () => {
  test('renders parent:child format for a 2-part path', () => {
    render(
      <PickerButton
        {...projectDefaults}
        data-label="ethiopia/feb-red-team"
        data-is-sandbox="true"
      />
    );
    const button = screen.getByRole('button');
    expect(button.textContent).toContain('ethiopia');
    expect(button.textContent).toContain('feb-red-team');
  });

  test('truncates deeper paths to ellipsis + last two segments', () => {
    render(
      <PickerButton
        {...projectDefaults}
        data-label="root/mid/deep/leaf"
        data-is-sandbox="true"
      />
    );
    const button = screen.getByRole('button');
    expect(button.textContent).toContain('deep');
    expect(button.textContent).toContain('leaf');
    expect(button.textContent).not.toContain('mid');
    expect(button.textContent).toContain('…');
  });

  test('applies the accent color as background', () => {
    render(
      <PickerButton
        {...projectDefaults}
        data-label="root/sandbox"
        data-is-sandbox="true"
        data-color="#E33D63"
      />
    );
    const button = screen.getByRole('button');
    expect(button.style.backgroundColor).toBe('rgb(227, 61, 99)');
  });
});

describe('PickerButton click', () => {
  test('dispatches the configured event on document.body', async () => {
    const user = userEvent.setup();
    const listener = vi.fn();
    document.body.addEventListener('open-billing-account-picker', listener);

    render(
      <PickerButton
        data-label="Acme Health"
        data-icon="hero-building-office"
        data-open-event="open-billing-account-picker"
      />
    );
    await user.click(screen.getByRole('button'));

    expect(listener).toHaveBeenCalledTimes(1);
    document.body.removeEventListener('open-billing-account-picker', listener);
  });
});
