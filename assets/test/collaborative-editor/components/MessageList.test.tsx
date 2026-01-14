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
  },
});

// Mock scrollIntoView
Element.prototype.scrollIntoView = vi.fn();

describe('MessageList', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('Empty State', () => {
    it('should render loading state when no messages', () => {
      render(<MessageList messages={[]} />);

      expect(screen.getByText(/Loading session/)).toBeInTheDocument();
    });

    it('should show spinner in loading state', () => {
      render(<MessageList messages={[]} />);

      const spinner = document.querySelector('.hero-arrow-path.animate-spin');
      expect(spinner).toBeInTheDocument();
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

      // Assistant message should have a different container than user
      // User messages have justify-end, assistant messages don't
      const userMessages = container.querySelectorAll('.justify-end');
      expect(userMessages.length).toBeGreaterThan(0);

      // Check that there's at least one message without justify-end (assistant)
      const allMessageContainers =
        container.querySelectorAll('[class*="flex"]');
      expect(allMessageContainers.length).toBeGreaterThan(userMessages.length);
    });
  });

  describe('Loading State', () => {
    it('should show loading session spinner when no messages', () => {
      render(<MessageList messages={[]} isLoading />);

      // When no messages, shows "Loading session..." regardless of isLoading
      expect(screen.getByText(/Loading session/)).toBeInTheDocument();
      const spinner = document.querySelector('.hero-arrow-path.animate-spin');
      expect(spinner).toBeInTheDocument();
    });

    it('should show loading session spinner even when isLoading is false and no messages', () => {
      render(<MessageList messages={[]} isLoading={false} />);

      // When no messages, shows "Loading session..." state
      expect(screen.getByText(/Loading session/)).toBeInTheDocument();
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

    it('should show APPLY button when showApplyButton is true', () => {
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

      render(
        <MessageList
          messages={messages}
          onApplyWorkflow={mockApply}
          showApplyButton
        />
      );

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
          showApplyButton
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
      // Mock clipboard API
      Object.assign(navigator, {
        clipboard: {
          writeText: vi.fn(() => Promise.resolve()),
        },
      });
    });

    it('should copy code to clipboard on COPY click', async () => {
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

    it('should show COPIED feedback after copying', async () => {
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

      const { container } = render(<MessageList messages={messages} />);

      // Should have whitespace-pre-wrap class to preserve newlines
      const textContainer = container.querySelector('.whitespace-pre-wrap');
      expect(textContainer).toBeInTheDocument();
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

      // Should not have code block with COPY/ADD buttons
      expect(screen.queryByText('Copy')).not.toBeInTheDocument();
      expect(screen.queryByText('ADD')).not.toBeInTheDocument();

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

      // Should not show APPLY button
      expect(screen.queryByText('APPLY')).not.toBeInTheDocument();
    });
  });
});
/* eslint-enable @typescript-eslint/unbound-method */
