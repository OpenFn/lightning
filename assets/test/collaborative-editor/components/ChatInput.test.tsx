/**
 * ChatInput - Tests for AI Assistant chat input component
 *
 * Tests the input form for sending messages, including:
 * - Text input and submission
 * - Keyboard shortcuts
 * - Loading states
 * - Job controls (attach code/logs)
 * - LocalStorage persistence
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { ChatInput } from '../../../js/collaborative-editor/components/ChatInput';

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

    it('should render keyboard hint', () => {
      render(<ChatInput />);

      expect(screen.getByText(/Press/)).toBeInTheDocument();
      expect(screen.getByText(/to send/)).toBeInTheDocument();
      expect(screen.getByText(/for new line/)).toBeInTheDocument();
    });

    it('should show warning about sensitive data by default', () => {
      render(<ChatInput />);

      expect(
        screen.getByText(/Do not include PII or sensitive data/)
      ).toBeInTheDocument();
    });

    it('should show job controls when showJobControls is true', () => {
      render(<ChatInput showJobControls />);

      expect(screen.getByText(/Include job code/)).toBeInTheDocument();
      expect(screen.getByText(/Include run logs/)).toBeInTheDocument();
      expect(screen.queryByText(/Do not include PII/)).not.toBeInTheDocument();
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

  describe('Job Controls', () => {
    it('should include attach_code and attach_logs options when showJobControls is true', async () => {
      render(<ChatInput onSendMessage={mockSendMessage} showJobControls />);

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test{Enter}');

      expect(mockSendMessage).toHaveBeenCalledWith('Test', {
        attach_code: true, // Default
        attach_logs: false, // Default
      });
    });

    it('should toggle attach_code checkbox', async () => {
      render(<ChatInput onSendMessage={mockSendMessage} showJobControls />);

      const codeCheckbox = screen.getByRole('checkbox', {
        name: /include job code/i,
      });

      // Default should be checked
      expect(codeCheckbox).toBeChecked();

      // Uncheck
      await userEvent.click(codeCheckbox);
      expect(codeCheckbox).not.toBeChecked();

      // Send message
      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test{Enter}');

      expect(mockSendMessage).toHaveBeenCalledWith('Test', {
        attach_code: false,
        attach_logs: false,
      });
    });

    it('should toggle attach_logs checkbox', async () => {
      render(<ChatInput onSendMessage={mockSendMessage} showJobControls />);

      const logsCheckbox = screen.getByRole('checkbox', {
        name: /include run logs/i,
      });

      // Default should be unchecked
      expect(logsCheckbox).not.toBeChecked();

      // Check
      await userEvent.click(logsCheckbox);
      expect(logsCheckbox).toBeChecked();

      // Send message
      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test{Enter}');

      expect(mockSendMessage).toHaveBeenCalledWith('Test', {
        attach_code: true,
        attach_logs: true,
      });
    });

    it('should not include options when showJobControls is false', async () => {
      render(
        <ChatInput onSendMessage={mockSendMessage} showJobControls={false} />
      );

      const textarea = screen.getByPlaceholderText('Ask me anything...');
      await userEvent.type(textarea, 'Test{Enter}');

      expect(mockSendMessage).toHaveBeenCalledWith('Test', {});
    });
  });

  describe('LocalStorage Persistence', () => {
    it('should load attach_code preference from localStorage', () => {
      localStorage.setItem('test-key:attach-code', 'false');

      render(<ChatInput showJobControls storageKey="test-key" />);

      const codeCheckbox = screen.getByRole('checkbox', {
        name: /include job code/i,
      });
      expect(codeCheckbox).not.toBeChecked();
    });

    it('should load attach_logs preference from localStorage', () => {
      localStorage.setItem('test-key:attach-logs', 'true');

      render(<ChatInput showJobControls storageKey="test-key" />);

      const logsCheckbox = screen.getByRole('checkbox', {
        name: /include run logs/i,
      });
      expect(logsCheckbox).toBeChecked();
    });

    it('should default to attach_code=true when not in localStorage', () => {
      render(<ChatInput showJobControls storageKey="test-key" />);

      const codeCheckbox = screen.getByRole('checkbox', {
        name: /include job code/i,
      });
      expect(codeCheckbox).toBeChecked();
    });

    it('should default to attach_logs=false when not in localStorage', () => {
      render(<ChatInput showJobControls storageKey="test-key" />);

      const logsCheckbox = screen.getByRole('checkbox', {
        name: /include run logs/i,
      });
      expect(logsCheckbox).not.toBeChecked();
    });

    it('should save attach_code preference to localStorage', async () => {
      render(<ChatInput showJobControls storageKey="test-key" />);

      const codeCheckbox = screen.getByRole('checkbox', {
        name: /include job code/i,
      });

      await userEvent.click(codeCheckbox);

      await waitFor(() => {
        expect(localStorage.getItem('test-key:attach-code')).toBe('false');
      });
    });

    it('should save attach_logs preference to localStorage', async () => {
      render(<ChatInput showJobControls storageKey="test-key" />);

      const logsCheckbox = screen.getByRole('checkbox', {
        name: /include run logs/i,
      });

      await userEvent.click(logsCheckbox);

      await waitFor(() => {
        expect(localStorage.getItem('test-key:attach-logs')).toBe('true');
      });
    });

    it('should update preferences when storageKey changes', async () => {
      localStorage.setItem('key-1:attach-code', 'false');
      localStorage.setItem('key-2:attach-code', 'true');

      const { rerender } = render(
        <ChatInput showJobControls storageKey="key-1" />
      );

      const codeCheckbox = screen.getByRole('checkbox', {
        name: /include job code/i,
      });
      expect(codeCheckbox).not.toBeChecked();

      // Change storageKey
      rerender(<ChatInput showJobControls storageKey="key-2" />);

      await waitFor(() => {
        expect(codeCheckbox).toBeChecked();
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
        render(<ChatInput showJobControls storageKey="test-key" />);
      }).not.toThrow();

      // Restore
      Storage.prototype.getItem = originalGetItem;
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
