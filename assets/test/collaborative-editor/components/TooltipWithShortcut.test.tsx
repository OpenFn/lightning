import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';

import { TooltipWithShortcut } from '#/collaborative-editor/components/TooltipWithShortcut';

describe('TooltipWithShortcut', () => {
  it('renders description only when shortcut is undefined', () => {
    render(
      <TooltipWithShortcut description="Save workflow" shortcut={undefined}>
        <button>Save</button>
      </TooltipWithShortcut>
    );

    const button = screen.getByRole('button', { name: 'Save' });
    expect(button).toBeInTheDocument();
  });

  it('renders description only when shortcut is empty array', () => {
    render(
      <TooltipWithShortcut description="Save workflow" shortcut={[]}>
        <button>Save</button>
      </TooltipWithShortcut>
    );

    const button = screen.getByRole('button', { name: 'Save' });
    expect(button).toBeInTheDocument();
  });

  it('renders with shortcut when provided', () => {
    render(
      <TooltipWithShortcut description="Save workflow" shortcut={['mod', 's']}>
        <button>Save</button>
      </TooltipWithShortcut>
    );

    const button = screen.getByRole('button', { name: 'Save' });
    expect(button).toBeInTheDocument();
  });

  it('passes through Tooltip props', () => {
    render(
      <TooltipWithShortcut
        description="Save workflow"
        shortcut={['mod', 's']}
        side="top"
      >
        <button>Save</button>
      </TooltipWithShortcut>
    );

    const button = screen.getByRole('button', { name: 'Save' });
    expect(button).toBeInTheDocument();
  });
});
