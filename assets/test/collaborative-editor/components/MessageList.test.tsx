/**
 * MessageList - Tests for AI Assistant message list component
 *
 * Tests the message display with markdown rendering, code blocks,
 * empty states, loading indicators, and user/assistant message styling.
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { MessageList } from '../../../js/collaborative-editor/components/MessageList';
import { createMockAIMessage } from '../__helpers__/aiAssistantHelpers';

// Mock clipboard API
Object.assign(navigator, {
  clipboard: {
    write: vi.fn(() => Promise.resolve()),
  },
});

// Mock scrollIntoView
Element.prototype.scrollIntoView = vi.fn();

describe('MessageList', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('Empty State', () => {
    it('should render empty state when no messages', () => {
      render(<MessageList messages={[]} />);

      expect(screen.getByText(/How can I help you today?/)).toBeInTheDocument();
      expect(
        screen.getByText(/I can help you build workflows/)
      ).toBeInTheDocument();
    });

    it('should show logo in empty state', () => {
      render(<MessageList messages={[]} />);

      const logo = screen.getByAltText('OpenFn');
      expect(logo).toBeInTheDocument();
      expect(logo).toHaveAttribute('src', '/images/logo.svg');
    });
  });

  describe('Message Rendering', () => {
    it('should render user messages', () => {
      const messages = [
        createMockAIMessage({ role: 'user', content: 'Hello AI' }),
      ];

      render(<MessageList messages={messages} />);

      expect(screen.getByText('Hello AI')).toBeInTheDocument();
    });

    it('should render assistant messages', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'Hello! How can I help you?',
        }),
      ];

      render(<MessageList messages={messages} />);

      expect(
        screen.getByText('Hello! How can I help you?')
      ).toBeInTheDocument();
    });

    it('should render multiple messages in order', () => {
      const messages = [
        createMockAIMessage({ id: '1', role: 'user', content: 'First' }),
        createMockAIMessage({ id: '2', role: 'assistant', content: 'Second' }),
        createMockAIMessage({ id: '3', role: 'user', content: 'Third' }),
      ];

      render(<MessageList messages={messages} />);

      const elements = screen.getAllByText(/First|Second|Third/);
      expect(elements).toHaveLength(3);
    });

    it('should apply different styles for user vs assistant', () => {
      const messages = [
        createMockAIMessage({ id: '1', role: 'user', content: 'User msg' }),
        createMockAIMessage({
          id: '2',
          role: 'assistant',
          content: 'Assistant msg',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      // User message should be right-aligned with bubble
      const userContainer = container.querySelector('.justify-end');
      expect(userContainer).toBeInTheDocument();

      // Assistant message should have gray background
      const assistantContainer = container.querySelector('.bg-gray-50\\/50');
      expect(assistantContainer).toBeInTheDocument();
    });
  });

  describe('Loading State', () => {
    it('should show loading indicator when isLoading is true', () => {
      render(<MessageList messages={[]} isLoading />);

      // Check for bouncing dots (multiple elements with animate-bounce)
      const bouncingDots = document.querySelectorAll('.animate-bounce');
      expect(bouncingDots.length).toBeGreaterThanOrEqual(3);
    });

    it('should not show loading indicator when isLoading is false', () => {
      render(<MessageList messages={[]} isLoading={false} />);

      const bouncingDots = document.querySelectorAll('.animate-bounce');
      expect(bouncingDots.length).toBe(0);
    });

    it('should show loading indicator below messages', () => {
      const messages = [
        createMockAIMessage({ role: 'user', content: 'Question' }),
      ];

      const { container } = render(
        <MessageList messages={messages} isLoading />
      );

      expect(screen.getByText('Question')).toBeInTheDocument();
      const bouncingDots = container.querySelectorAll('.animate-bounce');
      expect(bouncingDots.length).toBeGreaterThanOrEqual(3);
    });
  });

  describe('Message Status', () => {
    it('should show error state for failed messages', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'Failed message',
          status: 'error',
        }),
      ];

      render(<MessageList messages={messages} />);

      expect(screen.getByText(/Failed to send message/)).toBeInTheDocument();
    });

    it('should show processing state for processing messages', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'Processing...',
          status: 'processing',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      // Should have bouncing dots for processing state
      const bouncingDots = container.querySelectorAll('.animate-bounce');
      expect(bouncingDots.length).toBeGreaterThanOrEqual(3);
    });

    it('should show error for failed user messages', () => {
      const messages = [
        createMockAIMessage({
          role: 'user',
          content: 'Failed to send',
          status: 'error',
        }),
      ];

      render(<MessageList messages={messages} />);

      expect(screen.getByText(/Failed to send/i)).toBeInTheDocument();
    });
  });

  describe('Code Blocks', () => {
    it('should render code block when message has code property', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'Here is your workflow:',
          code: 'name: Test Workflow\njobs:\n  job1:\n    body: fn(state => state)',
        }),
      ];

      render(<MessageList messages={messages} />);

      expect(screen.getByText('Generated Workflow')).toBeInTheDocument();
    });

    it('should expand/collapse code block on click', async () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'Workflow:',
          code: 'name: Test\njobs: {}',
        }),
      ];

      render(<MessageList messages={messages} />);

      const expandButton = screen.getByText('Generated Workflow');

      // Initially collapsed
      expect(screen.queryByText('name: Test')).not.toBeInTheDocument();

      // Click to expand
      await userEvent.click(expandButton);
      expect(screen.getByText(/name: Test/)).toBeInTheDocument();

      // Click to collapse
      await userEvent.click(expandButton);
      await waitFor(() => {
        expect(screen.queryByText('name: Test')).not.toBeInTheDocument();
      });
    });

    it('should show COPY button for code blocks', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test code',
        }),
      ];

      render(<MessageList messages={messages} />);

      expect(screen.getByText('COPY')).toBeInTheDocument();
    });

    it('should show APPLY button when onApplyWorkflow provided', () => {
      const mockApply = vi.fn();
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'name: Test',
        }),
      ];

      render(<MessageList messages={messages} onApplyWorkflow={mockApply} />);

      expect(screen.getByText('APPLY')).toBeInTheDocument();
    });

    it('should call onApplyWorkflow when APPLY clicked', async () => {
      const mockApply = vi.fn();
      const messages = [
        createMockAIMessage({
          id: 'msg-1',
          role: 'assistant',
          code: 'name: Test',
        }),
      ];

      render(<MessageList messages={messages} onApplyWorkflow={mockApply} />);

      const applyButton = screen.getByText('APPLY');
      await userEvent.click(applyButton);

      expect(mockApply).toHaveBeenCalledWith('name: Test', 'msg-1');
    });

    it('should show APPLYING state during workflow apply', () => {
      const messages = [
        createMockAIMessage({
          id: 'msg-1',
          role: 'assistant',
          code: 'test',
        }),
      ];

      render(
        <MessageList
          messages={messages}
          onApplyWorkflow={vi.fn()}
          applyingMessageId="msg-1"
        />
      );

      expect(screen.getByText('APPLYING...')).toBeInTheDocument();
    });

    it('should show ADD button when showAddButtons is true', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test code',
        }),
      ];

      render(<MessageList messages={messages} showAddButtons />);

      expect(screen.getByText('ADD')).toBeInTheDocument();
    });

    it('should not show ADD button when showAddButtons is false', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test code',
        }),
      ];

      render(<MessageList messages={messages} showAddButtons={false} />);

      expect(screen.queryByText('ADD')).not.toBeInTheDocument();
    });
  });

  describe('Code Action Buttons', () => {
    beforeEach(() => {
      // Mock clipboard write
      vi.spyOn(navigator.clipboard, 'write').mockResolvedValue();
    });

    it('should copy code to clipboard on COPY click', async () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test code content',
        }),
      ];

      render(<MessageList messages={messages} />);

      const copyButton = screen.getByText('COPY');
      await userEvent.click(copyButton);

      await waitFor(() => {
        expect(navigator.clipboard.write).toHaveBeenCalled();
      });
    });

    it('should show COPIED feedback after copying', async () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test',
        }),
      ];

      render(<MessageList messages={messages} />);

      const copyButton = screen.getByText('COPY');
      await userEvent.click(copyButton);

      await waitFor(() => {
        expect(screen.getByText('COPIED')).toBeInTheDocument();
      });
    });

    it('should reset COPIED feedback after timeout', async () => {
      vi.useFakeTimers();

      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test',
        }),
      ];

      render(<MessageList messages={messages} />);

      const copyButton = screen.getByText('COPY');
      await userEvent.click(copyButton);

      // Wait for COPIED state
      await waitFor(() => {
        expect(screen.getByText('COPIED')).toBeInTheDocument();
      });

      // Fast-forward time
      vi.advanceTimersByTime(2000);

      await waitFor(() => {
        expect(screen.getByText('COPY')).toBeInTheDocument();
      });

      vi.useRealTimers();
    });

    it('should dispatch insert-snippet event on ADD click', async () => {
      const dispatchSpy = vi.spyOn(document, 'dispatchEvent');

      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'snippet code',
        }),
      ];

      render(<MessageList messages={messages} showAddButtons />);

      const addButton = screen.getByText('ADD');
      await userEvent.click(addButton);

      expect(dispatchSpy).toHaveBeenCalled();
      const event = dispatchSpy.mock.calls[0][0];
      expect(event.type).toBe('insert-snippet');
    });

    it('should show ADDED feedback after adding', async () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test',
        }),
      ];

      render(<MessageList messages={messages} showAddButtons />);

      const addButton = screen.getByText('ADD');
      await userEvent.click(addButton);

      await waitFor(() => {
        expect(screen.getByText('ADDED')).toBeInTheDocument();
      });
    });

    it('should show APPLIED feedback after applying', async () => {
      const messages = [
        createMockAIMessage({
          id: 'msg-1',
          role: 'assistant',
          code: 'test',
        }),
      ];

      render(<MessageList messages={messages} onApplyWorkflow={vi.fn()} />);

      const applyButton = screen.getByText('APPLY');
      await userEvent.click(applyButton);

      await waitFor(() => {
        expect(screen.getByText('APPLIED')).toBeInTheDocument();
      });
    });
  });

  describe('Markdown Rendering', () => {
    it('should render markdown content', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: '# Heading\n\nThis is **bold** text.',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      // Check for heading (h1 gets converted by marked)
      expect(container.querySelector('h1')).toBeInTheDocument();
      // Check for bold text (strong tag)
      expect(container.querySelector('strong')).toBeInTheDocument();
    });

    it('should render inline code', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'Use the `fn()` function.',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      expect(container.querySelector('code')).toBeInTheDocument();
      expect(container.querySelector('code')?.textContent).toContain('fn()');
    });

    it('should render lists', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: '- Item 1\n- Item 2\n- Item 3',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      const list = container.querySelector('ul');
      expect(list).toBeInTheDocument();
      expect(list?.querySelectorAll('li')).toHaveLength(3);
    });

    it('should render links', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'Visit [OpenFn](https://openfn.org)',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      const link = container.querySelector('a');
      expect(link).toBeInTheDocument();
      expect(link?.getAttribute('href')).toBe('https://openfn.org');
    });
  });

  describe('Auto-scroll Behavior', () => {
    it('should have scroll anchor at bottom', () => {
      const messages = [createMockAIMessage({ role: 'user', content: 'Test' })];

      const { container } = render(<MessageList messages={messages} />);

      // messagesEndRef creates an empty div at the bottom
      const scrollAnchor = container.querySelector(
        '.h-full.overflow-y-auto > div:last-child'
      );
      expect(scrollAnchor).toBeInTheDocument();
    });

    it('should render messages in scrollable container', () => {
      const messages = [createMockAIMessage({ role: 'user', content: 'Test' })];

      const { container } = render(<MessageList messages={messages} />);

      const scrollContainer = container.querySelector('.overflow-y-auto');
      expect(scrollContainer).toBeInTheDocument();
    });
  });

  describe('Props Handling', () => {
    it('should handle undefined messages prop', () => {
      render(<MessageList />);

      expect(screen.getByText(/How can I help you today?/)).toBeInTheDocument();
    });

    it('should handle empty messages array', () => {
      render(<MessageList messages={[]} />);

      expect(screen.getByText(/How can I help you today?/)).toBeInTheDocument();
    });

    it('should handle missing onApplyWorkflow', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test',
        }),
      ];

      render(<MessageList messages={messages} />);

      // Should not show APPLY button
      expect(screen.queryByText('APPLY')).not.toBeInTheDocument();
    });
  });
});
