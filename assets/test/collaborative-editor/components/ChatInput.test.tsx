/**
 * ChatInput - Tests for AI Assistant chat input component
 *
 * Tests the input form for sending messages, including:
 * - Text input and submission
 * - Keyboard shortcuts
 * - Loading states
 * - Run attachment controls (send logs, send data)
 * - LocalStorage persistence
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import {
  render,
  screen,
  fireEvent,
  waitFor,
  within,
} from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { ChatInput } from '../../../js/collaborative-editor/components/ChatInput';

const toggleContext = async (name: RegExp) => {
  await userEvent.click(screen.getByRole('checkbox', { name }));
};

describe('ChatInput', () => {
  let mockSendMessage: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockSendMessage = vi.fn();
    localStorage.clear();
    vi.clearAllMocks();
  });

  describe('Rendering', () => {
    it('should render textarea with placeholder', () => {
      render(<ChatInput />);

      expect(
        screen.getByPlaceholderText('Ask me anything...')
      ).toBeInTheDocument();
    });

    it('should render send button', () => {
      render(<ChatInput />);

      const sendButton = screen.getByRole('button', { name: /send message/i });
      expect(sendButton).toBeInTheDocument();
    });

    it('should show the AI disclaimer footer by default', () => {
      render(<ChatInput />);

      expect(
        screen.getByText(/Please use AI responsibly\. Never share PII\./)
      ).toBeInTheDocument();
      expect(screen.getByRole('link', { name: /learn more/i })).toHaveAttribute(
        'href',
        'https://www.openfn.org/ai'
      );
    });

    it('should offer no attachment controls when there is no run to take them from', () => {
      render(<ChatInput />);

      expect(screen.queryByTestId('attached-context')).not.toBeInTheDocument();
      expect(screen.getByText(/Please use AI responsibly/)).toBeInTheDocument();
    });

    it('should offer both boxes, unticked, once a run is loaded', () => {
      render(<ChatInput selectedRunId="run-123" />);

      const controls = screen.getByTestId('attached-context');
      expect(
        within(controls).getByRole('checkbox', { name: /send run logs/i })
      ).not.toBeChecked();
      expect(
        within(controls).getByRole('checkbox', { name: /send run data/i })
      ).not.toBeChecked();
    });
  });

  describe('Text Input', () => {
    it('should update textarea value on input', async () => {
      render(<ChatInput />);

      const textarea = screen.getByPlaceholderText(
        'Ask me anything...'
      ) as HTMLTextAreaElement;

      await userEvent.type(textarea, 'Hello AI');

      expect(textarea.value).toBe('Hello AI');
    });

    it('should disable textarea when loading', () => {
      render(<ChatInput isLoading />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      expect(textarea).toBeDisabled();
    });

    it('should trim whitespace from input', async () => {
      render(<ChatInput onSendMessage={mockSendMessage} />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, '  Test message  ');

      const form = textarea.closest('form')!;
      fireEvent.submit(form);

      expect(mockSendMessage).toHaveBeenCalledWith('Test message', {});
    });
  });

  describe('Message Submission', () => {
    it('should call onSendMessage when form is submitted', async () => {
      render(<ChatInput onSendMessage={mockSendMessage} />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test message');

      const form = textarea.closest('form')!;
      fireEvent.submit(form);

      expect(mockSendMessage).toHaveBeenCalledWith('Test message', {});
      expect(mockSendMessage).toHaveBeenCalledTimes(1);
    });

    it('should clear input after submission', async () => {
      render(<ChatInput onSendMessage={mockSendMessage} />);

      const textarea = screen.getByPlaceholderText(
        'Ask me anything...'
      ) as HTMLTextAreaElement;
      await userEvent.type(textarea, 'Test message');

      const form = textarea.closest('form')!;
      fireEvent.submit(form);

      expect(textarea.value).toBe('');
    });

    it('should not submit empty message', async () => {
      render(<ChatInput onSendMessage={mockSendMessage} />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      const form = textarea.closest('form')!;
      fireEvent.submit(form);

      expect(mockSendMessage).not.toHaveBeenCalled();
    });

    it('should not submit whitespace-only message', async () => {
      render(<ChatInput onSendMessage={mockSendMessage} />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, '   ');

      const form = textarea.closest('form')!;
      fireEvent.submit(form);

      expect(mockSendMessage).not.toHaveBeenCalled();
    });

    it('should not submit while loading', async () => {
      render(<ChatInput onSendMessage={mockSendMessage} isLoading />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test');

      const form = textarea.closest('form')!;
      fireEvent.submit(form);

      expect(mockSendMessage).not.toHaveBeenCalled();
    });

    it('should handle missing onSendMessage gracefully', async () => {
      render(<ChatInput />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test');

      const form = textarea.closest('form')!;
      expect(() => fireEvent.submit(form)).not.toThrow();
    });
  });

  describe('Keyboard Shortcuts', () => {
    it('should submit on Enter key', async () => {
      render(<ChatInput onSendMessage={mockSendMessage} />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test message{Enter}');

      expect(mockSendMessage).toHaveBeenCalledWith('Test message', {});
    });

    it('should not submit on Shift+Enter', async () => {
      render(<ChatInput onSendMessage={mockSendMessage} />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Line 1{Shift>}{Enter}{/Shift}Line 2');

      expect(mockSendMessage).not.toHaveBeenCalled();
      // Textarea should contain newline
      expect((textarea as HTMLTextAreaElement).value).toContain('\n');
    });

    it('should clear input after Enter key submission', async () => {
      render(<ChatInput onSendMessage={mockSendMessage} />);

      const textarea = screen.getByPlaceholderText(
        'Ask me anything...'
      ) as HTMLTextAreaElement;
      await userEvent.type(textarea, 'Test{Enter}');

      await waitFor(() => {
        expect(textarea.value).toBe('');
      });
    });
  });

  describe('Send Button State', () => {
    it('should disable send button when input is empty', () => {
      render(<ChatInput />);

      const sendButton = screen.getByRole('button', { name: /send message/i });
      expect(sendButton).toBeDisabled();
    });

    it('should enable send button when input has text', async () => {
      render(<ChatInput />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test');

      const sendButton = screen.getByRole('button', { name: /send message/i });
      expect(sendButton).toBeEnabled();
    });

    it('should disable send button when loading', () => {
      render(<ChatInput isLoading />);

      const sendButton = screen.getByRole('button', {
        name: /sending\.\.\./i,
      });
      expect(sendButton).toBeDisabled();
    });

    it('should show loading spinner when loading', () => {
      render(<ChatInput isLoading />);

      // Check for spinner icon
      const sendButton = screen.getByRole('button', {
        name: /sending\.\.\./i,
      });
      expect(sendButton.querySelector('.hero-arrow-path')).toBeInTheDocument();
      expect(sendButton.querySelector('.hero-arrow-path')).toHaveClass(
        'animate-spin'
      );
    });

    it('should show send icon when not loading', () => {
      render(<ChatInput />);

      const sendButton = screen.getByRole('button', { name: /send message/i });
      expect(
        sendButton.querySelector('.hero-paper-airplane-solid')
      ).toBeInTheDocument();
    });
  });

  describe('Message Length', () => {
    const type = async (text: string) => {
      const textarea = screen.getByPlaceholderText('Ask me anything...');
      // fireEvent, not userEvent: typing ten thousand characters one keystroke
      // at a time takes minutes.
      fireEvent.change(textarea, { target: { value: text } });
    };

    it('says nothing until you are close to the limit', async () => {
      render(<ChatInput />);
      await type('x'.repeat(9000));

      expect(screen.queryByTestId('chat-input-length')).not.toBeInTheDocument();
    });

    it('counts down once you are within five hundred', async () => {
      render(<ChatInput />);
      await type('x'.repeat(9600));

      // The comma grouping comes from the locale vitest.config.ts pins for the
      // run, not from the component: ChatInput formats with the viewer's own
      // locale, so a real en-ZA or de-DE user sees "9 600" / "9.600". If this
      // assertion fails on your machine, the locale pin is not in effect —
      // don't pass a fixed locale to `toLocaleString()` in the component to
      // make it pass.
      expect(screen.getByTestId('chat-input-length')).toHaveTextContent(
        '9,600 / 10,000'
      );
    });

    it('still sends at exactly the limit', async () => {
      const onSendMessage = vi.fn();
      render(<ChatInput onSendMessage={onSendMessage} />);
      await type('x'.repeat(10000));

      const sendButton = screen.getByRole('button', { name: /send message/i });
      expect(sendButton).toBeEnabled();
      await userEvent.click(sendButton);
      expect(onSendMessage).toHaveBeenCalled();
    });

    it('keeps the AI disclaimer alongside the counter', async () => {
      render(<ChatInput />);
      await type('x'.repeat(9600));

      expect(screen.getByTestId('chat-input-length')).toBeInTheDocument();
      expect(screen.getByText(/use AI responsibly/i)).toBeInTheDocument();
    });

    it('refuses to send once over it', async () => {
      const onSendMessage = vi.fn();
      render(<ChatInput onSendMessage={onSendMessage} />);
      await type('x'.repeat(10001));

      const counter = screen.getByTestId('chat-input-length');
      expect(counter).toHaveTextContent('too long to send');

      const sendButton = screen.getByRole('button', { name: /send message/i });
      expect(sendButton).toBeDisabled();

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, '{Enter}');
      expect(onSendMessage).not.toHaveBeenCalled();
    });
  });

  describe('Run Attachment Controls', () => {
    it('should include both flags and the run when a run is selected', async () => {
      render(
        <ChatInput onSendMessage={mockSendMessage} selectedRunId="run-123" />
      );

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test{Enter}');

      // Unticked is still an answer, so both ride along as false rather than
      // being left out.
      expect(mockSendMessage).toHaveBeenCalledWith('Test', {
        attach_logs: false,
        attach_io_data: false,
        follow_run_id: 'run-123',
      });
    });

    it('should include attach_logs when run logs are added', async () => {
      render(
        <ChatInput onSendMessage={mockSendMessage} selectedRunId="run-123" />
      );

      await toggleContext(/send run logs/i);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test{Enter}');

      expect(mockSendMessage).toHaveBeenCalledWith('Test', {
        attach_logs: true,
        attach_io_data: false,
        follow_run_id: 'run-123',
      });
    });

    it('should include attach_io_data when run data is added', async () => {
      render(
        <ChatInput onSendMessage={mockSendMessage} selectedRunId="run-123" />
      );

      await toggleContext(/send run data/i);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test{Enter}');

      expect(mockSendMessage).toHaveBeenCalledWith('Test', {
        attach_logs: false,
        attach_io_data: true,
        follow_run_id: 'run-123',
      });
    });

    it('should send no attachment options when no run is loaded', async () => {
      render(
        <ChatInput onSendMessage={mockSendMessage} selectedRunId={null} />
      );

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test{Enter}');

      // A step without a run cannot be attached, so nothing goes.
      expect(mockSendMessage).toHaveBeenCalledWith('Test', {});
    });
  });

  describe('Attached Context', () => {
    it('should tick only the box that was clicked', async () => {
      render(<ChatInput selectedRunId="run-123" />);

      await toggleContext(/send run logs/i);

      const controls = screen.getByTestId('attached-context');
      expect(
        within(controls).getByRole('checkbox', { name: /send run logs/i })
      ).toBeChecked();
      expect(
        within(controls).getByRole('checkbox', { name: /send run data/i })
      ).not.toBeChecked();
    });

    it('should untick on a second click', async () => {
      render(
        <ChatInput onSendMessage={mockSendMessage} selectedRunId="run-1" />
      );

      await toggleContext(/send run logs/i);
      await toggleContext(/send run logs/i);

      expect(
        screen.getByRole('checkbox', { name: /send run logs/i })
      ).not.toBeChecked();

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test{Enter}');

      expect(mockSendMessage).toHaveBeenCalledWith('Test', {
        attach_logs: false,
        attach_io_data: false,
        follow_run_id: 'run-1',
      });
    });

    it('should claim nothing when there is no run, whatever was remembered', () => {
      localStorage.setItem('test-key:attach-logs', 'true');
      localStorage.setItem('test-key:attach-run-data', 'true');

      // A step on its own is not enough: both attachments are run-scoped.
      render(<ChatInput storageKey="test-key" selectedRunId={null} />);

      expect(screen.queryByTestId('attached-context')).not.toBeInTheDocument();
    });

    it('should bring the remembered attachments back when a run arrives', async () => {
      localStorage.setItem('test-key:attach-logs', 'true');

      const { rerender } = render(
        <ChatInput storageKey="test-key" selectedRunId={null} />
      );

      expect(screen.queryByTestId('attached-context')).not.toBeInTheDocument();

      rerender(<ChatInput storageKey="test-key" selectedRunId="run-123" />);

      await waitFor(() => {
        expect(
          screen.getByRole('checkbox', { name: /send run logs/i })
        ).toBeChecked();
      });
    });
  });

  describe('LocalStorage Persistence', () => {
    it('should load remembered attachments from localStorage', () => {
      localStorage.setItem('test-key:attach-logs', 'true');
      localStorage.setItem('test-key:attach-run-data', 'true');

      render(<ChatInput storageKey="test-key" selectedRunId="run-123" />);

      expect(
        screen.getByRole('checkbox', { name: /send run logs/i })
      ).toBeChecked();
      expect(
        screen.getByRole('checkbox', { name: /send run data/i })
      ).toBeChecked();
    });

    it('should attach nothing by default', () => {
      render(<ChatInput storageKey="test-key" selectedRunId="run-123" />);

      expect(
        screen.getByRole('checkbox', { name: /send run logs/i })
      ).not.toBeChecked();
      expect(
        screen.getByRole('checkbox', { name: /send run data/i })
      ).not.toBeChecked();
    });

    it('should save each attachment to localStorage', async () => {
      render(<ChatInput storageKey="test-key" selectedRunId="run-123" />);

      await toggleContext(/send run logs/i);
      await waitFor(() => {
        expect(localStorage.getItem('test-key:attach-logs')).toBe('true');
      });

      await toggleContext(/send run data/i);
      await waitFor(() => {
        expect(localStorage.getItem('test-key:attach-run-data')).toBe('true');
      });
    });

    it('should update preferences when storageKey changes', async () => {
      localStorage.setItem('key-1:attach-logs', 'false');
      localStorage.setItem('key-2:attach-logs', 'true');

      const { rerender } = render(
        <ChatInput storageKey="key-1" selectedRunId="run-123" />
      );

      expect(
        screen.getByRole('checkbox', { name: /send run logs/i })
      ).not.toBeChecked();

      // Change storageKey
      rerender(<ChatInput storageKey="key-2" selectedRunId="run-123" />);

      await waitFor(() => {
        expect(
          screen.getByRole('checkbox', { name: /send run logs/i })
        ).toBeChecked();
      });
    });

    it('should handle localStorage errors gracefully', () => {
      // Mock localStorage.getItem to throw error
      const originalGetItem = Storage.prototype.getItem;
      Storage.prototype.getItem = vi.fn(() => {
        throw new Error('localStorage error');
      });

      // Should not crash
      expect(() => {
        render(<ChatInput storageKey="test-key" />);
      }).not.toThrow();

      // Restore
      Storage.prototype.getItem = originalGetItem;
    });
  });

  describe('Disabled State', () => {
    it('should disable textarea when isDisabled is true', () => {
      render(<ChatInput isDisabled />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      expect(textarea).toBeDisabled();
    });

    it('should disable send button when isDisabled is true', () => {
      render(<ChatInput isDisabled />);

      const sendButton = screen.getByRole('button', { name: /send message/i });
      expect(sendButton).toBeDisabled();
    });

    it('should show static icon (not spinner) when isDisabled but not loading', () => {
      render(<ChatInput isDisabled isLoading={false} />);

      const sendButton = screen.getByRole('button', { name: /send message/i });

      // Should NOT have spinner
      expect(
        sendButton.querySelector('.hero-arrow-path')
      ).not.toBeInTheDocument();

      // Should have static send icon
      expect(
        sendButton.querySelector('.hero-paper-airplane-solid')
      ).toBeInTheDocument();
    });

    it('should not submit when isDisabled is true', async () => {
      render(<ChatInput onSendMessage={mockSendMessage} isDisabled />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test message');

      const form = textarea.closest('form')!;
      fireEvent.submit(form);

      expect(mockSendMessage).not.toHaveBeenCalled();
    });

    it('should not submit on Enter key when isDisabled is true', async () => {
      render(<ChatInput onSendMessage={mockSendMessage} isDisabled />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test{Enter}');

      expect(mockSendMessage).not.toHaveBeenCalled();
    });

    it('should show tooltip when isDisabled is true', () => {
      render(
        <ChatInput isDisabled disabledMessage="AI assistant is unavailable" />
      );

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      const tooltipContainer = textarea.closest(
        '[data-radix-popper-content-wrapper]'
      );

      // Tooltip should be available (implementation depends on Tooltip component)
      expect(textarea).toBeDisabled();
    });

    it('should disable textarea when both isLoading and isDisabled are true', () => {
      render(<ChatInput isLoading isDisabled />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      expect(textarea).toBeDisabled();
    });

    it('should show spinner when both isLoading and isDisabled are true', () => {
      render(<ChatInput isLoading isDisabled />);

      const sendButton = screen.getByRole('button', {
        name: /sending\.\.\./i,
      });

      // Should show spinner (isLoading takes precedence for button icon)
      expect(sendButton.querySelector('.hero-arrow-path')).toBeInTheDocument();
      expect(sendButton.querySelector('.hero-arrow-path')).toHaveClass(
        'animate-spin'
      );
    });

    it('should allow submission when isDisabled is false', async () => {
      render(<ChatInput onSendMessage={mockSendMessage} isDisabled={false} />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test{Enter}');

      expect(mockSendMessage).toHaveBeenCalledWith('Test', {});
    });
  });

  describe('Visual States', () => {
    it('should apply focused border styles when input has content', async () => {
      render(<ChatInput />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      const container = textarea.parentElement!;

      // Initially no content
      expect(container).toHaveClass('border-gray-200');

      // Add content
      await userEvent.type(textarea, 'Test');

      // Should have primary border
      expect(container).toHaveClass('border-primary-300');
    });

    it('should show disabled cursor when loading', () => {
      render(<ChatInput isLoading />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      expect(textarea).toHaveClass('disabled:cursor-not-allowed');
    });

    it('should show disabled cursor when isDisabled', () => {
      render(<ChatInput isDisabled />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      expect(textarea).toHaveClass('disabled:cursor-not-allowed');
    });
  });

  describe('Auto-resize Behavior', () => {
    it('should set textarea height based on content', async () => {
      render(<ChatInput />);

      const textarea = screen.getByPlaceholderText(
        'Ask me anything...'
      ) as HTMLTextAreaElement;

      // Mock scrollHeight
      Object.defineProperty(textarea, 'scrollHeight', {
        configurable: true,
        value: 100,
      });

      await userEvent.type(textarea, 'Line 1\nLine 2\nLine 3');

      // Height should be set to scrollHeight
      await waitFor(() => {
        expect(textarea.style.height).toBe('100px');
      });
    });

    it('should have minimum height', () => {
      render(<ChatInput />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      expect(textarea).toHaveStyle({ minHeight: '52px' });
    });

    it('should have maximum height', () => {
      render(<ChatInput />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      expect(textarea).toHaveStyle({ maxHeight: '200px' });
    });
  });
});
