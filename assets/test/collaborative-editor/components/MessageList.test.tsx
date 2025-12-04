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

// Mock clipboard API and ClipboardItem
global.ClipboardItem = class ClipboardItem {
  constructor(public data: Record<string, Blob>) {}
} as any;

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

    it('should render GFM tables with alignment', () => {
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

      // Check alignment attributes are preserved
      const leftTh = container.querySelector('th[align="left"]');
      const centerTh = container.querySelector('th[align="center"]');
      const rightTh = container.querySelector('th[align="right"]');
      expect(leftTh).toBeInTheDocument();
      expect(centerTh).toBeInTheDocument();
      expect(rightTh).toBeInTheDocument();
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

  describe('XSS Sanitization', () => {
    it('should strip script tags from content', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'Hello <script>alert("xss")</script> world',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      expect(container.querySelector('script')).not.toBeInTheDocument();
      expect(container.textContent).toContain('Hello');
      expect(container.textContent).toContain('world');
      expect(container.textContent).not.toContain('alert');
    });

    it('should strip onerror handlers from img tags', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: '<img src="x" onerror="alert(\'xss\')">',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      // img tag itself should be stripped (not in allowed tags)
      expect(container.querySelector('img')).not.toBeInTheDocument();
    });

    it('should strip onclick handlers', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: '<a href="#" onclick="alert(\'xss\')">Click me</a>',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      const link = container.querySelector('a');
      expect(link).toBeInTheDocument();
      expect(link?.getAttribute('onclick')).toBeNull();
    });

    it('should strip iframe tags', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: '<iframe src="https://evil.com"></iframe>',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      expect(container.querySelector('iframe')).not.toBeInTheDocument();
    });

    it('should strip javascript: URLs from links', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: '<a href="javascript:alert(\'xss\')">Click</a>',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      const link = container.querySelector('a');
      expect(link).toBeInTheDocument();
      // DOMPurify removes javascript: URLs entirely (href becomes null)
      expect(link?.getAttribute('href')).toBeNull();
    });

    it('should strip style attributes', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content:
            '<p style="background:url(javascript:alert(\'xss\'))">Styled</p>',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      const p = container.querySelector('p');
      expect(p).toBeInTheDocument();
      expect(p?.getAttribute('style')).toBeNull();
    });

    it('should preserve safe markdown while stripping dangerous HTML', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content:
            '# Safe Heading\n\n<script>bad()</script>\n\n**Bold** and [link](https://safe.com)',
        }),
      ];

      const { container } = render(<MessageList messages={messages} />);

      // Safe content preserved
      expect(container.querySelector('h1')).toBeInTheDocument();
      expect(container.querySelector('strong')).toBeInTheDocument();
      expect(container.querySelector('a')?.getAttribute('href')).toBe(
        'https://safe.com'
      );

      // Dangerous content removed
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
