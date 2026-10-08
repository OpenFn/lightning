import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect, beforeEach, vi } from 'vitest';

import { ChatInput } from '../../../js/collaborative-editor/components/ChatInput';

const skills = [
  { name: 'diagnose', description: 'Find out why a run failed' },
  { name: 'qa', description: 'Review this workflow' },
];

describe('ChatInput slash commands', () => {
  let onSendMessage: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    onSendMessage = vi.fn();
    render(<ChatInput onSendMessage={onSendMessage} skills={skills} />);
  });

  const input = () => screen.getByTestId('chat-input');

  it('offers every skill for a leading slash, filtered as you type', async () => {
    await userEvent.type(input(), '/');
    expect(screen.getAllByRole('option').map(o => o.textContent)).toEqual([
      expect.stringContaining('/diagnose'),
      expect.stringContaining('/qa'),
    ]);

    await userEvent.type(input(), 'q');
    expect(screen.getAllByRole('option')).toHaveLength(1);
  });

  it('offers nothing for a slash after the first token', async () => {
    await userEvent.type(input(), 'run /');
    expect(screen.queryByTestId('skill-menu')).not.toBeInTheDocument();
  });

  it('highlights the chosen skill and sends it as a command', async () => {
    await userEvent.type(input(), '/');
    await userEvent.click(screen.getByRole('option', { name: /\/qa/ }));

    expect(screen.getByTestId('skill-command')).toHaveTextContent('/qa');
    expect(input()).toHaveValue('');

    await userEvent.type(input(), 'the new step{Enter}');
    expect(onSendMessage).toHaveBeenCalledWith('/qa the new step', {});
    expect(screen.queryByTestId('skill-command')).not.toBeInTheDocument();
  });

  it('picks the highlighted skill with the keyboard', async () => {
    await userEvent.type(input(), '/{ArrowDown}{Enter}');

    expect(screen.getByTestId('skill-command')).toHaveTextContent('/qa');
    expect(onSendMessage).not.toHaveBeenCalled();
  });

  it('highlights a typed command at the space after its name', async () => {
    await userEvent.type(input(), '/diagnose why');

    expect(screen.getByTestId('skill-command')).toHaveTextContent('/diagnose');
    expect(input()).toHaveValue('why');
  });

  it('sends a command with no details', async () => {
    await userEvent.type(input(), '/qa {Enter}');
    expect(onSendMessage).toHaveBeenCalledWith('/qa', {});
  });

  it('leaves an unknown command as text', async () => {
    await userEvent.type(input(), '/explain this');

    expect(screen.queryByTestId('skill-command')).not.toBeInTheDocument();
    expect(input()).toHaveValue('/explain this');
  });

  it('removes the command on backspace at the start, keeping the details', async () => {
    await userEvent.type(input(), '/qa x{ArrowLeft}{Backspace}');

    expect(screen.queryByTestId('skill-command')).not.toBeInTheDocument();
    expect(input()).toHaveValue('x');
  });

  it('closes the menu on Escape so Enter sends the text', async () => {
    await userEvent.type(input(), '/q{Escape}{Enter}');

    expect(screen.queryByTestId('skill-menu')).not.toBeInTheDocument();
    expect(onSendMessage).toHaveBeenCalledWith('/q', {});
  });
});
