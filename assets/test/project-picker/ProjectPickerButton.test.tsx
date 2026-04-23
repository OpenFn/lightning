import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test, vi } from 'vitest';

import { ProjectPickerButton } from '#/project-picker/ProjectPickerButton';

describe('ProjectPickerButton non-sandbox', () => {
  test('renders the plain label', () => {
    render(<ProjectPickerButton data-label="ethiopia" />);
    expect(
      screen.getByRole('button', { name: /ethiopia/ })
    ).toBeInTheDocument();
  });

  test('does not apply background color styling', () => {
    render(<ProjectPickerButton data-label="ethiopia" data-color="#abcdef" />);
    const button = screen.getByRole('button');
    expect(button.style.backgroundColor).toBe('');
  });
});

describe('ProjectPickerButton sandbox', () => {
  test('renders parent:child format for a 2-part path', () => {
    render(
      <ProjectPickerButton
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
      <ProjectPickerButton
        data-label="root/mid/deep/leaf"
        data-is-sandbox="true"
      />
    );
    const button = screen.getByRole('button');
    // Visible text should include the last two parts
    expect(button.textContent).toContain('deep');
    expect(button.textContent).toContain('leaf');
    // Middle ancestors should not be in the rendered label
    expect(button.textContent).not.toContain('mid');
    // Ellipsis indicates truncation
    expect(button.textContent).toContain('…');
  });

  test('applies the accent color as background', () => {
    render(
      <ProjectPickerButton
        data-label="root/sandbox"
        data-is-sandbox="true"
        data-color="#E33D63"
      />
    );
    const button = screen.getByRole('button');
    // React normalizes hex to rgb
    expect(button.style.backgroundColor).toBe('rgb(227, 61, 99)');
  });
});

describe('ProjectPickerButton click', () => {
  test('dispatches open-project-picker on document.body', async () => {
    const user = userEvent.setup();
    const listener = vi.fn();
    document.body.addEventListener('open-project-picker', listener);

    render(<ProjectPickerButton data-label="ethiopia" />);
    await user.click(screen.getByRole('button'));

    expect(listener).toHaveBeenCalledTimes(1);
    document.body.removeEventListener('open-project-picker', listener);
  });
});
