/**
 * ChatInterface - Tests for AI Assistant chat interface
 *
 * Tests the full chat interface including message display and input.
 * This is a simpler component that combines MessageList-like display with input.
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { ChatInterface } from '../../../js/collaborative-editor/components/ChatInterface';
import { createMockAIMessage } from '../__helpers__/aiAssistantHelpers';

describe('ChatInterface', () => {
  let mockSendMessage: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockSendMessage = vi.fn();
    vi.clearAllMocks();
  });

  describe('Empty State', () => {
    it('should render empty state when no messages', () => {
      render(<ChatInterface messages={[]} />);

      expect(screen.getByText(/How can I help you today?/)).toBeInTheDocument();
    });

    it('should show logo in empty state', () => {
      render(<ChatInterface messages={[]} />);

      const logo = screen.getByAltText('OpenFn');
      expect(logo).toBeInTheDocument();
      expect(logo).toHaveAttribute('src', '/images/logo.svg');
    });

    it('should show helpful description', () => {
      render(<ChatInterface messages={[]} />);

      expect(
        screen.getByText(/I can help you build workflows/)
      ).toBeInTheDocument();
    });
  });

  describe('Message Display', () => {
    it('should render user messages', () => {
      const messages = [
        createMockAIMessage({ role: 'user', content: 'Hello AI' }),
      ];

      render(<ChatInterface messages={messages} />);

      expect(screen.getByText('Hello AI')).toBeInTheDocument();
    });

    it('should render assistant messages', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'Hello! How can I help?',
        }),
      ];

      render(<ChatInterface messages={messages} />);

      expect(screen.getByText('Hello! How can I help?')).toBeInTheDocument();
    });

    it('should render multiple messages', () => {
      const messages = [
        createMockAIMessage({ id: '1', role: 'user', content: 'Question' }),
        createMockAIMessage({ id: '2', role: 'assistant', content: 'Answer' }),
      ];

      render(<ChatInterface messages={messages} />);

      expect(screen.getByText('Question')).toBeInTheDocument();
      expect(screen.getByText('Answer')).toBeInTheDocument();
    });

    it('should show code block for messages with code', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'Here is a workflow:',
          code: 'name: Test\njobs: {}',
        }),
      ];

      render(<ChatInterface messages={messages} />);

      expect(screen.getByText('Workflow YAML')).toBeInTheDocument();
      expect(screen.getByText(/name: Test/)).toBeInTheDocument();
    });

    it('should show error state for failed messages', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'Message',
          status: 'error',
        }),
      ];

      render(<ChatInterface messages={messages} />);

      expect(screen.getByText(/Failed to send message/)).toBeInTheDocument();
    });

    it('should show processing state with animated dots', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'Thinking...',
          status: 'processing',
        }),
      ];

      const { container } = render(<ChatInterface messages={messages} />);

      const dots = container.querySelectorAll('.animate-bounce');
      expect(dots.length).toBeGreaterThanOrEqual(3);
    });

    it('should show error for failed user messages', () => {
      const messages = [
        createMockAIMessage({
          role: 'user',
          content: 'Failed',
          status: 'error',
        }),
      ];

      render(<ChatInterface messages={messages} />);

      expect(screen.getByText(/Failed to send/)).toBeInTheDocument();
    });
  });

  describe('Input Field', () => {
    it('should render input textarea', () => {
      render(<ChatInterface />);

      expect(
        screen.getByPlaceholderText('Message Assistant...')
      ).toBeInTheDocument();
    });

    it('should update textarea value on input', async () => {
      render(<ChatInterface />);

      const textarea = screen.getByPlaceholderText(
        'Message Assistant...'
      ) as HTMLTextAreaElement;

      await userEvent.type(textarea, 'Test message');

      expect(textarea.value).toBe('Test message');
    });

    it('should disable textarea when loading', () => {
      render(<ChatInterface isLoading />);

      const textarea = screen.getByPlaceholderText('Message Assistant...');
      expect(textarea).toBeDisabled();
    });

    it('should show warning about sensitive data', () => {
      render(<ChatInterface />);

      expect(
        screen.getByText(/Do not include PII or sensitive data/)
      ).toBeInTheDocument();
    });
  });

  describe('Message Submission', () => {
    it('should call onSendMessage when form submitted', async () => {
      render(<ChatInterface onSendMessage={mockSendMessage} />);

      const textarea = screen.getByPlaceholderText('Message Assistant...');
      await userEvent.type(textarea, 'Test message');

      const form = textarea.closest('form')!;
      await userEvent.click(screen.getByRole('button', { name: /send/i }));

      expect(mockSendMessage).toHaveBeenCalledWith('Test message');
    });

    it('should clear input after submission', async () => {
      render(<ChatInterface onSendMessage={mockSendMessage} />);

      const textarea = screen.getByPlaceholderText(
        'Message Assistant...'
      ) as HTMLTextAreaElement;
      await userEvent.type(textarea, 'Test');

      await userEvent.click(screen.getByRole('button', { name: /send/i }));

      expect(textarea.value).toBe('');
    });

    it('should not submit empty message', async () => {
      render(<ChatInterface onSendMessage={mockSendMessage} />);

      const sendButton = screen.getByRole('button', { name: /send/i });
      await userEvent.click(sendButton);

      expect(mockSendMessage).not.toHaveBeenCalled();
    });

    it('should trim whitespace from message', async () => {
      render(<ChatInterface onSendMessage={mockSendMessage} />);

      const textarea = screen.getByPlaceholderText('Message Assistant...');
      await userEvent.type(textarea, '  Hello  ');

      await userEvent.click(screen.getByRole('button', { name: /send/i }));

      expect(mockSendMessage).toHaveBeenCalledWith('Hello');
    });

    it('should not submit while loading', async () => {
      render(<ChatInterface onSendMessage={mockSendMessage} isLoading />);

      const textarea = screen.getByPlaceholderText('Message Assistant...');
      await userEvent.type(textarea, 'Test');

      const sendButton = screen.getByRole('button', { name: /sending/i });
      await userEvent.click(sendButton);

      expect(mockSendMessage).not.toHaveBeenCalled();
    });

    it('should submit on Enter key', async () => {
      render(<ChatInterface onSendMessage={mockSendMessage} />);

      const textarea = screen.getByPlaceholderText('Message Assistant...');
      await userEvent.type(textarea, 'Test{Enter}');

      expect(mockSendMessage).toHaveBeenCalledWith('Test');
    });

    it('should not submit on Shift+Enter', async () => {
      render(<ChatInterface onSendMessage={mockSendMessage} />);

      const textarea = screen.getByPlaceholderText('Message Assistant...');
      await userEvent.type(textarea, 'Line 1{Shift>}{Enter}{/Shift}Line 2');

      expect(mockSendMessage).not.toHaveBeenCalled();
      expect((textarea as HTMLTextAreaElement).value).toContain('\n');
    });
  });

  describe('Send Button', () => {
    it('should render send button', () => {
      render(<ChatInterface />);

      expect(
        screen.getByRole('button', { name: /send message/i })
      ).toBeInTheDocument();
    });

    it('should disable send button when input empty', () => {
      render(<ChatInterface />);

      const sendButton = screen.getByRole('button', { name: /send/i });
      expect(sendButton).toBeDisabled();
    });

    it('should enable send button when input has text', async () => {
      render(<ChatInterface />);

      const textarea = screen.getByPlaceholderText('Message Assistant...');
      await userEvent.type(textarea, 'Test');

      const sendButton = screen.getByRole('button', { name: /send/i });
      expect(sendButton).toBeEnabled();
    });

    it('should show loading spinner when loading', () => {
      render(<ChatInterface isLoading />);

      const sendButton = screen.getByRole('button', { name: /sending/i });
      expect(sendButton.querySelector('.animate-spin')).toBeInTheDocument();
    });

    it('should show send icon when not loading', () => {
      render(<ChatInterface />);

      const sendButton = screen.getByRole('button', { name: /send/i });
      expect(
        sendButton.querySelector('.hero-paper-airplane-solid')
      ).toBeInTheDocument();
    });
  });

  describe('Layout', () => {
    it('should have scrollable message area', () => {
      const messages = [createMockAIMessage({ role: 'user', content: 'Test' })];

      const { container } = render(<ChatInterface messages={messages} />);

      const scrollArea = container.querySelector('.overflow-y-auto');
      expect(scrollArea).toBeInTheDocument();
    });

    it('should have fixed input area at bottom', () => {
      const { container } = render(<ChatInterface />);

      const inputArea = container.querySelector('.flex-none');
      expect(inputArea).toBeInTheDocument();
    });

    it('should use full height layout', () => {
      const { container } = render(<ChatInterface />);

      const layout = container.querySelector('.h-full');
      expect(layout).toBeInTheDocument();
    });
  });

  describe('Keyboard Hint', () => {
    it('should show keyboard shortcuts hint', () => {
      render(<ChatInterface />);

      expect(screen.getByText(/Press/)).toBeInTheDocument();
      expect(screen.getByText(/to send/)).toBeInTheDocument();
      expect(screen.getByText(/for new line/)).toBeInTheDocument();
    });
  });

  describe('Props Handling', () => {
    it('should handle undefined messages', () => {
      render(<ChatInterface />);

      expect(screen.getByText(/How can I help you today?/)).toBeInTheDocument();
    });

    it('should handle missing onSendMessage', async () => {
      render(<ChatInterface />);

      const textarea = screen.getByPlaceholderText('Message Assistant...');
      await userEvent.type(textarea, 'Test');

      const form = textarea.closest('form')!;
      expect(() =>
        userEvent.click(screen.getByRole('button', { name: /send/i }))
      ).not.toThrow();
    });

    it('should default isLoading to false', () => {
      render(<ChatInterface />);

      const textarea = screen.getByPlaceholderText('Message Assistant...');
      expect(textarea).not.toBeDisabled();
    });
  });

  describe('Message Styling', () => {
    it('should apply different backgrounds for user vs assistant', () => {
      const messages = [
        createMockAIMessage({ id: '1', role: 'user', content: 'User' }),
        createMockAIMessage({ id: '2', role: 'assistant', content: 'AI' }),
      ];

      const { container } = render(<ChatInterface messages={messages} />);

      // Assistant message has gray background
      const assistantBg = container.querySelector('.bg-gray-50\\/50');
      expect(assistantBg).toBeInTheDocument();

      // User message is right-aligned
      const userAlign = container.querySelector('.justify-end');
      expect(userAlign).toBeInTheDocument();
    });

    it('should style user messages as bubbles', () => {
      const messages = [createMockAIMessage({ role: 'user', content: 'Test' })];

      const { container } = render(<ChatInterface messages={messages} />);

      const bubble = container.querySelector('.rounded-2xl');
      expect(bubble).toBeInTheDocument();
    });
  });
});
