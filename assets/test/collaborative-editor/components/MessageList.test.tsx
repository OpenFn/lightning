/**
 * MessageList - Tests for AI Assistant message list component
 *
 * Tests the message display with markdown rendering, code blocks,
 * empty states, loading indicators, and user/assistant message styling.
 */

/* eslint-disable @typescript-eslint/unbound-method */
// Disabled because we reference navigator.clipboard.writeText in expect() calls
// which TypeScript sees as an unbound method. This is safe in tests where we're
// checking if the mocked method was called, not actually calling it.
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect, beforeEach, vi } from 'vitest';

import { MessageList } from '../../../js/collaborative-editor/components/MessageList';
import { createMockAIMessage } from '../__helpers__/aiAssistantHelpers';

// Mock clipboard API and ClipboardItem
global.ClipboardItem = class ClipboardItem {
  constructor(public data: Record<string, Blob>) {}
} as any;

Object.assign(navigator, {
  clipboard: {
    writeText: vi.fn(() => Promise.resolve()),
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
    it('should show "Loading session..." state when messages array is empty', () => {
      const { rerender } = render(<MessageList messages={[]} />);

      expect(screen.getByTestId('empty-state')).toBeInTheDocument();
      expect(screen.getByText(/Loading session/)).toBeInTheDocument();

      // Spinner should be visible
      const spinner = document.querySelector('.hero-arrow-path.animate-spin');
      expect(spinner).toBeInTheDocument();

      // Verify isLoading prop doesn't affect empty state
      rerender(<MessageList messages={[]} isLoading={false} />);
      expect(screen.getByTestId('empty-state')).toBeInTheDocument();
      expect(screen.getByText(/Loading session/)).toBeInTheDocument();
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

      render(<MessageList messages={messages} />);

      const userMessage = screen.getByTestId('user-message');
      const assistantMessage = screen.getByTestId('assistant-message');

      // Both messages should exist
      expect(userMessage).toBeInTheDocument();
      expect(assistantMessage).toBeInTheDocument();

      // User message should be right-aligned (justify-end class)
      expect(userMessage).toHaveClass('justify-end');

      // User message should have a bubble (rounded-2xl with background)
      const userBubble = userMessage.querySelector('.rounded-2xl.bg-gray-100');
      expect(userBubble).toBeInTheDocument();

      // Assistant message should NOT have justify-end (left-aligned)
      expect(assistantMessage).not.toHaveClass('justify-end');

      // Both messages should have their content
      expect(screen.getByText('User msg')).toBeInTheDocument();
      expect(screen.getByText('Assistant msg')).toBeInTheDocument();
    });
  });

  describe('Loading State', () => {
    it('should show loading indicator below messages when isLoading is true', () => {
      const messages = [
        createMockAIMessage({ role: 'user', content: 'Question' }),
      ];

      render(<MessageList messages={messages} isLoading />);

      expect(screen.getByText('Question')).toBeInTheDocument();
      expect(screen.getByTestId('loading-indicator')).toBeInTheDocument();

      // Should have three bouncing dots
      const loadingIndicator = screen.getByTestId('loading-indicator');
      const bouncingDots = loadingIndicator.querySelectorAll('.animate-bounce');
      expect(bouncingDots).toHaveLength(3);
    });

    it('should not show loading indicator when isLoading is false', () => {
      const messages = [
        createMockAIMessage({ role: 'user', content: 'Question' }),
      ];

      render(<MessageList messages={messages} isLoading={false} />);

      expect(screen.getByText('Question')).toBeInTheDocument();
      expect(screen.queryByTestId('loading-indicator')).not.toBeInTheDocument();
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
          content: 'My message',
          status: 'error',
        }),
      ];

      render(<MessageList messages={messages} />);

      // User message error shows the message content
      expect(screen.getByText('My message')).toBeInTheDocument();
      // And an error indicator
      const errorElements = screen.getAllByText(/Failed to send/i);
      expect(errorElements.length).toBeGreaterThan(0);
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

      const expandButton = screen.getByTestId('expand-code-button');

      // Initially collapsed - code element should not be in DOM
      expect(screen.queryByTestId('generated-code')).not.toBeInTheDocument();

      // Click to expand
      await userEvent.click(expandButton);
      expect(screen.getByTestId('generated-code')).toBeInTheDocument();
      expect(screen.getByText(/name: Test/)).toBeInTheDocument();

      // Click to collapse - code element should be removed from DOM
      await userEvent.click(expandButton);
      await waitFor(() => {
        expect(screen.queryByTestId('generated-code')).not.toBeInTheDocument();
      });
    });

    it('should show Copy button for code blocks', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test code',
        }),
      ];

      render(<MessageList messages={messages} />);

      const copyButtons = screen.getAllByText('Copy');
      expect(copyButtons.length).toBeGreaterThan(0);
    });

    it('should show "Apply" button when showApplyButton is true', () => {
      const mockApply = vi.fn();
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'name: Test',
        }),
      ];

      render(
        <MessageList
          messages={messages}
          onApplyWorkflow={mockApply}
          showApplyButton
        />
      );

      expect(screen.getByText('Apply')).toBeInTheDocument();
    });

    it('should call onApplyWorkflow when "Apply" clicked', async () => {
      const mockApply = vi.fn();
      const messages = [
        createMockAIMessage({
          id: 'msg-1',
          role: 'assistant',
          code: 'name: Test',
        }),
      ];

      render(
        <MessageList
          messages={messages}
          onApplyWorkflow={mockApply}
          showApplyButton
        />
      );

      const applyButton = screen.getByText('Apply');
      await userEvent.click(applyButton);

      expect(mockApply).toHaveBeenCalledWith('name: Test', 'msg-1');
    });

    it('should show "Applying" state during workflow apply', () => {
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
          showApplyButton
          applyingMessageId="msg-1"
        />
      );

      expect(screen.getByText('Applying...')).toBeInTheDocument();
    });

    it('should show "Add" button when showAddButtons is true', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test code',
        }),
      ];

      render(<MessageList messages={messages} showAddButtons />);

      expect(screen.getByText('Add')).toBeInTheDocument();
    });

    it('should not show Add button when showAddButtons is false', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test code',
        }),
      ];

      render(<MessageList messages={messages} showAddButtons={false} />);

      expect(screen.queryByText('Add')).not.toBeInTheDocument();
    });
  });

  describe('Code Action Buttons', () => {
    beforeEach(() => {
      // Mock clipboard API
      Object.assign(navigator, {
        clipboard: {
          writeText: vi.fn(() => Promise.resolve()),
          write: vi.fn(() => Promise.resolve()),
        },
      });
    });

    it('should copy code to clipboard on "Copy" click', async () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test code content',
        }),
      ];

      render(<MessageList messages={messages} />);

      // Get all Copy buttons - there are multiple (code block + message footer)
      // Click the first one and verify the correct content was copied
      const copyButtons = screen.getAllByText('Copy');
      await userEvent.click(copyButtons[0]);

      await waitFor(() => {
        expect(navigator.clipboard.writeText).toHaveBeenCalledWith(
          'test code content'
        );
      });
    });

    it('should show "Copied" feedback after copying', async () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test',
        }),
      ];

      render(<MessageList messages={messages} />);

      // Get all Copy buttons - click one and verify feedback appears
      const copyButtons = screen.getAllByText('Copy');
      await userEvent.click(copyButtons[0]);

      await waitFor(() => {
        expect(screen.getByText('Copied!')).toBeInTheDocument();
      });
    });

    it('should handle rapid sequential copy clicks', async () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test code',
        }),
      ];

      render(<MessageList messages={messages} />);

      const copyButtons = screen.getAllByText('Copy');

      // Click multiple times rapidly
      await userEvent.click(copyButtons[0]);
      await userEvent.click(copyButtons[0]);
      await userEvent.click(copyButtons[0]);

      // Should still work - clipboard called 3 times
      expect(navigator.clipboard.writeText).toHaveBeenCalledTimes(3);
      expect(navigator.clipboard.writeText).toHaveBeenCalledWith('test code');
    });

    it('should handle copy failure gracefully', async () => {
      // Spy on console.error to verify error is logged but not thrown
      const consoleErrorSpy = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {});

      // Mock clipboard.writeText to reject for this specific test
      // Code blocks use writeText (via useCopyToClipboard hook)
      const writeTextSpy = vi
        .spyOn(navigator.clipboard, 'writeText')
        .mockRejectedValueOnce(new Error('Clipboard access denied'));

      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test',
        }),
      ];

      render(<MessageList messages={messages} />);

      const copyButtons = screen.getAllByText('Copy');
      await userEvent.click(copyButtons[0]);

      // Should not throw error - handle gracefully
      await waitFor(() => {
        expect(writeTextSpy).toHaveBeenCalled();
        expect(consoleErrorSpy).toHaveBeenCalledWith(
          'Failed to copy to clipboard:',
          expect.any(Error)
        );
      });

      consoleErrorSpy.mockRestore();
      writeTextSpy.mockRestore();
    });
  });

  describe('User Message Plain Text Rendering', () => {
    it('should render user messages as plain text without markdown processing', () => {
      const messages = [
        createMockAIMessage({
          role: 'user',
          content: '**bold** and `code` with [link](https://test.com)',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      // Markdown syntax should not be processed
      expect(container.querySelector('strong')).not.toBeInTheDocument();
      expect(container.querySelector('a')).not.toBeInTheDocument();

      // Content should display literally
      expect(container.textContent).toContain('**bold**');
      expect(container.textContent).toContain('`code`');
      expect(container.textContent).toContain('[link](https://test.com)');
    });

    it('should preserve newlines and formatting in user messages', () => {
      const messages = [
        createMockAIMessage({
          role: 'user',
          content: 'Line 1\nLine 2\nLine 3',
        }),
      ];

      render(<MessageList messages={messages} />);

      // User message should exist
      const userMessage = screen.getByTestId('user-message');
      expect(userMessage).toBeInTheDocument();

      // Should have whitespace-pre-wrap class to preserve newlines
      const textContainer = userMessage.querySelector('.whitespace-pre-wrap');
      expect(textContainer).toBeInTheDocument();

      // Should preserve exact text content with newlines
      expect(textContainer?.textContent).toBe('Line 1\nLine 2\nLine 3');
    });

    it('should not render code blocks for multi-line user content', () => {
      const messages = [
        createMockAIMessage({
          role: 'user',
          content: 'const foo = "bar";\nconst baz = "qux";\nconsole.log(foo);',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      // Should not have code block with Copy/Add buttons
      expect(screen.queryByText('Copy')).not.toBeInTheDocument();
      expect(screen.queryByText('Add')).not.toBeInTheDocument();

      // Should not have pre/code block styling
      expect(container.querySelector('pre')).not.toBeInTheDocument();
    });
  });

  describe('Markdown Rendering', () => {
    it('should render markdown content for assistant messages', () => {
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

    it('should render GFM tables', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content:
            '| Left | Center | Right |\n|:-----|:------:|------:|\n| L | C | R |',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      const table = container.querySelector('table');
      expect(table).toBeInTheDocument();
      expect(container.querySelector('thead')).toBeInTheDocument();
      expect(container.querySelector('tbody')).toBeInTheDocument();

      // Check table cells are rendered
      const headerCells = container.querySelectorAll('th');
      expect(headerCells).toHaveLength(3);
      expect(headerCells[0]?.textContent).toBe('Left');
      expect(headerCells[1]?.textContent).toBe('Center');
      expect(headerCells[2]?.textContent).toBe('Right');
    });

    it('should render strikethrough text', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'This is ~~deleted~~ text.',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      const del = container.querySelector('del');
      expect(del).toBeInTheDocument();
      expect(del?.textContent).toBe('deleted');
    });

    it('should render horizontal rules', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'Above\n\n---\n\nBelow',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      expect(container.querySelector('hr')).toBeInTheDocument();
    });
  });

  describe('XSS Prevention', () => {
    // react-markdown does not render raw HTML by default - it treats it as text
    // This is more secure than sanitizing because HTML is never parsed

    it('should not render script tags from raw HTML', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'Hello <script>alert("xss")</script> world',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      // Script tag is not rendered as an element
      expect(container.querySelector('script')).not.toBeInTheDocument();
      // Content around the script tag is preserved
      expect(container.textContent).toContain('Hello');
      expect(container.textContent).toContain('world');
    });

    it('should not render img tags from raw HTML', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: '<img src="x" onerror="alert(\'xss\')">',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      // img tag is not rendered as an element
      expect(container.querySelector('img')).not.toBeInTheDocument();
    });

    it('should not render raw HTML anchor tags', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: '<a href="#" onclick="alert(\'xss\')">Click me</a>',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      // Raw HTML anchor is not rendered - only markdown links work
      // The text content may be visible but not as an anchor element
      expect(container.querySelector('a[onclick]')).not.toBeInTheDocument();
    });

    it('should not render iframe tags from raw HTML', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: '<iframe src="https://evil.com"></iframe>',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      expect(container.querySelector('iframe')).not.toBeInTheDocument();
    });

    it('should render safe markdown links correctly', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: '[Safe Link](https://safe.com)',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      const link = container.querySelector('a');
      expect(link).toBeInTheDocument();
      expect(link?.getAttribute('href')).toBe('https://safe.com');
    });

    it('should preserve safe markdown while ignoring raw HTML', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content:
            '# Safe Heading\n\n<script>bad()</script>\n\n**Bold** and [link](https://safe.com)',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      // Safe markdown content is preserved
      expect(container.querySelector('h1')).toBeInTheDocument();
      expect(container.querySelector('strong')).toBeInTheDocument();
      expect(container.querySelector('a')?.getAttribute('href')).toBe(
        'https://safe.com'
      );

      // Raw HTML script is not rendered
      expect(container.querySelector('script')).not.toBeInTheDocument();
    });
  });

  describe('Auto-scroll Behavior', () => {
    it('should call scrollIntoView when new messages are added', () => {
      const { rerender } = render(
        <MessageList messages={[createMockAIMessage({ content: 'First' })]} />
      );

      expect(Element.prototype.scrollIntoView).toHaveBeenCalledWith({
        behavior: 'smooth',
        block: 'end',
      });

      vi.clearAllMocks();

      // Add another message
      rerender(
        <MessageList
          messages={[
            createMockAIMessage({ id: '1', content: 'First' }),
            createMockAIMessage({ id: '2', content: 'Second' }),
          ]}
        />
      );

      // Should scroll again with new message
      expect(Element.prototype.scrollIntoView).toHaveBeenCalledWith({
        behavior: 'smooth',
        block: 'end',
      });
    });

    it('should render messages in scrollable container', () => {
      const messages = [createMockAIMessage({ role: 'user', content: 'Test' })];

      render(<MessageList messages={messages} />);

      // Use semantic query via data-testid
      expect(screen.getByTestId('message-list')).toBeInTheDocument();
    });
  });

  describe('Props Handling', () => {
    it('should handle undefined messages prop', () => {
      render(<MessageList />);

      expect(screen.getByText(/Loading session/)).toBeInTheDocument();
    });

    it('should handle empty messages array', () => {
      render(<MessageList messages={[]} />);

      expect(screen.getByText(/Loading session/)).toBeInTheDocument();
    });

    it('should handle missing onApplyWorkflow', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          code: 'test',
        }),
      ];

      render(<MessageList messages={messages} />);

      // Should not show "Apply" button
      expect(screen.queryByText('Apply')).not.toBeInTheDocument();
    });
  });
});
/* eslint-enable @typescript-eslint/unbound-method */
