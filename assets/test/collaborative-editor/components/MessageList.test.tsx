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
import {
  render,
  screen,
  fireEvent,
  waitFor,
  within,
} from '@testing-library/react';
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

    it('should show streaming status below the text answer once content has streamed', () => {
      const messages = [
        createMockAIMessage({ role: 'user', content: 'Question' }),
      ];

      render(
        <MessageList
          messages={messages}
          isLoading
          streamingContent="Here is the answer"
          streamingStatus="Generating code..."
        />
      );

      // Pre-text loading indicator is gone once content streams in
      expect(screen.queryByTestId('loading-indicator')).not.toBeInTheDocument();

      // Status renders below the streamed text, reusing the bouncing dots
      const status = screen.getByTestId('streaming-status');
      expect(status).toHaveTextContent('Generating code...');
      expect(status.querySelectorAll('.animate-bounce')).toHaveLength(3);
    });

    it('should not show streaming status when none is set', () => {
      const messages = [
        createMockAIMessage({ role: 'user', content: 'Question' }),
      ];

      render(
        <MessageList
          messages={messages}
          streamingContent="Here is the answer"
        />
      );

      expect(screen.queryByTestId('streaming-status')).not.toBeInTheDocument();
    });
  });

  describe('Message Status', () => {
    it('should show error content in styled box for assistant error with content', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'YAML parse failed: unexpected token',
          status: 'error',
        }),
      ];

      render(<MessageList messages={messages} />);

      // Non-empty content renders inline in a red validation error box
      expect(screen.getByTestId('ai-validation-error')).toBeInTheDocument();
      expect(
        screen.getByText('YAML parse failed: unexpected token')
      ).toBeInTheDocument();
    });

    it('should show "Failed to send message" banner for assistant error with no content', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: '',
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

  describe('Global Messages (from_global)', () => {
    it('renders no YAML panel and no action buttons for global messages', () => {
      const onApplyWorkflow = vi.fn();
      const messages = [
        createMockAIMessage({
          id: 'msg-global',
          role: 'assistant',
          content: 'Done.',
          code: 'name: Test\njobs: {}',
          from_global: true,
        }),
      ];

      render(
        <MessageList
          messages={messages}
          onApplyWorkflow={onApplyWorkflow}
          showApplyButton
          showAddButtons
        />
      );

      // Global changes auto-apply, so the whole Generated Workflow block
      // disappears — no panel, no Apply/Copy/Preview/Add row. The diff
      // blocks are the entire representation of the change.
      expect(screen.queryByText('Generated Workflow')).not.toBeInTheDocument();
      expect(
        screen.queryByTestId('expand-code-button')
      ).not.toBeInTheDocument();
      expect(screen.queryByText('Apply')).not.toBeInTheDocument();
      expect(screen.queryByText('Preview')).not.toBeInTheDocument();
      expect(screen.queryByText('Add')).not.toBeInTheDocument();
      // The only Copy left is the message-footer copy, not a code action
      expect(
        screen.queryByTestId('apply-workflow-button')
      ).not.toBeInTheDocument();
    });

    it('keeps job-code messages unchanged: Preview routes to onPreviewJobCode', async () => {
      const onPreviewJobCode = vi.fn();
      const onApplyWorkflow = vi.fn();
      const onApplyJobCode = vi.fn();
      const messages = [
        createMockAIMessage({
          id: 'msg-job',
          role: 'assistant',
          code: 'fn(state => state)',
          job_id: 'job-1',
        }),
      ];

      render(
        <MessageList
          messages={messages}
          onPreviewJobCode={onPreviewJobCode}
          onApplyWorkflow={onApplyWorkflow}
          onApplyJobCode={onApplyJobCode}
          showApplyButton
        />
      );

      expect(screen.getByText('Generated Job Code')).toBeInTheDocument();

      await userEvent.click(screen.getByText('Preview'));
      expect(onPreviewJobCode).toHaveBeenCalledWith(
        'fn(state => state)',
        'msg-job'
      );

      await userEvent.click(screen.getByText('Apply'));
      expect(onApplyJobCode).toHaveBeenCalledWith(
        'fn(state => state)',
        'msg-job'
      );
      expect(onApplyWorkflow).not.toHaveBeenCalled();
    });
  });

  describe('Workflow Diff Blocks (global messages)', () => {
    const workflowYaml = (body: string) =>
      [
        'id: wf-1',
        'name: Test Workflow',
        'jobs:',
        '  transform-data:',
        '    id: job-1',
        '    name: Transform data',
        "    adaptor: '@openfn/language-common@latest'",
        '    body: |',
        `      ${body}`,
        'triggers:',
        '  webhook:',
        '    id: trigger-1',
        '    type: webhook',
        '    enabled: true',
        'edges:',
        '  webhook->transform-data:',
        '    id: edge-1',
        '    source_trigger: webhook',
        '    target_job: transform-data',
        '    condition_type: always',
        '    enabled: true',
      ].join('\n') + '\n';

    /** Two-step workflow: webhook -> Transform data -> Send to Gmail */
    const twoStepYaml = (transformBody: string, gmailBody: string) =>
      [
        'id: wf-1',
        'name: Test Workflow',
        'jobs:',
        '  transform-data:',
        '    id: job-1',
        '    name: Transform data',
        "    adaptor: '@openfn/language-common@latest'",
        '    body: |',
        `      ${transformBody}`,
        '  send-to-gmail:',
        '    id: job-2',
        '    name: Send to Gmail',
        "    adaptor: '@openfn/language-gmail@latest'",
        '    body: |',
        `      ${gmailBody}`,
        'triggers:',
        '  webhook:',
        '    id: trigger-1',
        '    type: webhook',
        '    enabled: true',
        'edges:',
        '  webhook->transform-data:',
        '    id: edge-1',
        '    source_trigger: webhook',
        '    target_job: transform-data',
        '    condition_type: always',
        '    enabled: true',
        '  transform-data->send-to-gmail:',
        '    id: edge-2',
        '    source_job: transform-data',
        '    target_job: send-to-gmail',
        '    condition_type: on_job_success',
        '    enabled: true',
      ].join('\n') + '\n';

    describe('while the reply is still streaming', () => {
      const userMessage = (code: string) =>
        createMockAIMessage({
          id: 'msg-user',
          role: 'user',
          content: 'Change the transform',
          code,
        });

      it('renders the diff as soon as the snapshot lands, before the reply settles', () => {
        const before = workflowYaml('fn(state => state);');
        const after = workflowYaml('fn(state => state.data);');

        render(
          <MessageList
            messages={[userMessage(before)]}
            isGlobalAssistantActive
            streamingSegments={[
              { type: 'status', content: 'Edited workflow structure' },
            ]}
            streamingSnapshots={[{ yaml: after, segmentIndex: 0 }]}
          />
        );

        // The blocks used to wait for the persisted message, which is what
        // made every diff appear at once when the stream ended.
        expect(screen.getByTestId('streaming-message')).toBeInTheDocument();
        expect(screen.getByTestId('diff-block-header')).toHaveTextContent(
          'Update(Transform data)'
        );
      });

      it('renders each action under the status that announced it', () => {
        const before = twoStepYaml('fn(s => s);', 'fn(s => s);');
        const first = twoStepYaml('fn(s => s.data);', 'fn(s => s);');
        const second = twoStepYaml('fn(s => s.data);', 'fn(s => s.mail);');

        render(
          <MessageList
            messages={[userMessage(before)]}
            isGlobalAssistantActive
            streamingSegments={[
              { type: 'status', content: 'Wrote code for "Transform data"' },
              { type: 'status', content: 'Wrote code for "Send to Gmail"' },
            ]}
            streamingSnapshots={[
              { yaml: first, segmentIndex: 0 },
              { yaml: second, segmentIndex: 1 },
            ]}
          />
        );

        const groups = screen.getAllByTestId('status-step-diffs');
        expect(groups).toHaveLength(2);
        expect(
          within(groups[0]!).getByTestId('diff-block-header')
        ).toHaveTextContent('Update(Transform data)');
        expect(
          within(groups[1]!).getByTestId('diff-block-header')
        ).toHaveTextContent('Update(Send to Gmail)');
      });

      it('attributes by snapshot, not by name, when the status never names the step', () => {
        const before = workflowYaml('fn(state => state);');
        const after = workflowYaml('fn(state => state.data);');

        render(
          <MessageList
            messages={[userMessage(before)]}
            isGlobalAssistantActive
            streamingSegments={[{ type: 'status', content: 'Made an edit' }]}
            streamingSnapshots={[{ yaml: after, segmentIndex: 0 }]}
          />
        );

        // The old prose-matching path needed the step name in the status
        // text; the snapshot pairing does not.
        const group = screen.getByTestId('status-step-diffs');
        expect(
          within(group).getByTestId('diff-block-header')
        ).toHaveTextContent('Update(Transform data)');
      });

      it('holds a snapshot below the timeline until its status arrives', () => {
        const before = workflowYaml('fn(state => state);');
        const after = workflowYaml('fn(state => state.data);');

        render(
          <MessageList
            messages={[userMessage(before)]}
            isGlobalAssistantActive
            streamingSegments={[{ type: 'status', content: 'Planning' }]}
            streamingSnapshots={[{ yaml: after, segmentIndex: 1 }]}
          />
        );

        // Pinned past the last drained segment — render it at the end
        // rather than dropping it.
        expect(
          screen.queryByTestId('status-step-diffs')
        ).not.toBeInTheDocument();
        expect(screen.getByTestId('workflow-diff-blocks')).toBeInTheDocument();
      });

      it('keeps the same blocks when the reply settles with its snapshots', () => {
        const before = workflowYaml('fn(state => state);');
        const after = workflowYaml('fn(state => state.data);');
        const segments = [
          { type: 'status' as const, content: 'Edited workflow structure' },
        ];

        const { rerender } = render(
          <MessageList
            messages={[userMessage(before)]}
            isGlobalAssistantActive
            streamingSegments={segments}
            streamingSnapshots={[{ yaml: after, segmentIndex: 0 }]}
          />
        );

        const streamed = screen.getByTestId('status-step-diffs').innerHTML;

        // The stream ends: the placeholder goes away and the persisted
        // message arrives carrying the same snapshots.
        rerender(
          <MessageList
            messages={[
              userMessage(before),
              createMockAIMessage({
                id: 'msg-global',
                role: 'assistant',
                content: 'Done.',
                code: after,
                from_global: true,
                response_segments: segments,
              }),
            ]}
            isGlobalAssistantActive
            snapshotsByMessageId={{
              'msg-global': [{ yaml: after, segmentIndex: 0 }],
            }}
          />
        );

        expect(screen.getByTestId('assistant-message')).toBeInTheDocument();
        expect(screen.getByTestId('status-step-diffs').innerHTML).toBe(
          streamed
        );
      });
    });

    it('renders a diff block with header and red/green rows for a changed step', () => {
      const messages = [
        createMockAIMessage({
          id: 'msg-user',
          role: 'user',
          content: 'Change the transform',
          code: workflowYaml('fn(state => state);'),
        }),
        createMockAIMessage({
          id: 'msg-global',
          role: 'assistant',
          content: 'Done, I updated the step.',
          code: workflowYaml('fn(state => state.data);'),
          from_global: true,
        }),
      ];

      render(<MessageList messages={messages} />);

      expect(screen.getByTestId('workflow-diff-blocks')).toBeInTheDocument();
      expect(screen.getByTestId('diff-block')).toBeInTheDocument();
      expect(screen.getByTestId('diff-block-header')).toHaveTextContent(
        'Update(Transform data)'
      );
      expect(screen.getByTestId('diff-block-summary')).toHaveTextContent(
        '+1 -1'
      );

      // Every block starts expanded, with red/green rows
      const removed = screen.getByTestId('diff-line-removed');
      const added = screen.getByTestId('diff-line-added');
      expect(removed).toHaveTextContent('fn(state => state);');
      expect(removed).toHaveClass('bg-[#ffebe9]');
      expect(added).toHaveTextContent('fn(state => state.data);');
      expect(added).toHaveClass('bg-[#e6ffec]');
    });

    it('renders a Structure block for edge/trigger changes', () => {
      const before = workflowYaml('fn(state => state);');
      const after = before.replace(
        'type: webhook\n    enabled: true',
        'type: webhook\n    enabled: false'
      );
      const messages = [
        createMockAIMessage({
          id: 'msg-user',
          role: 'user',
          content: 'Disable the trigger',
          code: before,
        }),
        createMockAIMessage({
          id: 'msg-global',
          role: 'assistant',
          content: 'Disabled it.',
          code: after,
          from_global: true,
        }),
      ];

      render(<MessageList messages={messages} />);

      expect(screen.getByTestId('structure-block')).toBeInTheDocument();
      const row = screen.getByTestId('structure-row');
      expect(row).toHaveTextContent('webhook trigger');
      expect(row.getAttribute('data-change')).toBe('modify');
      // No step bodies changed -> no per-step diff blocks
      expect(screen.queryByTestId('diff-block')).not.toBeInTheDocument();
    });

    it('renders all-adds diff when the preceding user message has no code', () => {
      const messages = [
        createMockAIMessage({
          id: 'msg-user',
          role: 'user',
          content: 'Build me a workflow',
          // no code: client had no workflow to serialize
        }),
        createMockAIMessage({
          id: 'msg-global',
          role: 'assistant',
          content: 'Here you go.',
          code: workflowYaml('fn(state => state);'),
          from_global: true,
        }),
      ];

      render(<MessageList messages={messages} />);

      // Step block plus a Structure block (trigger + edge adds)
      const headers = screen.getAllByTestId('diff-block-header');
      expect(headers[0]).toHaveTextContent('Add(Transform data)');
      expect(headers[1]).toHaveTextContent('Structure');
      const structureRows = screen.getAllByTestId('structure-row');
      expect(structureRows).toHaveLength(2);
      structureRows.forEach(row => {
        expect(row.getAttribute('data-change')).toBe('add');
      });
      // Every block starts expanded, add blocks included
      expect(screen.getByTestId('diff-line-added')).toBeInTheDocument();
    });

    it('renders nothing when the workflow is unchanged', () => {
      const yaml = workflowYaml('fn(state => state);');
      const messages = [
        createMockAIMessage({
          id: 'msg-user',
          role: 'user',
          content: 'Just answer a question',
          code: yaml,
        }),
        createMockAIMessage({
          id: 'msg-global',
          role: 'assistant',
          content: 'No changes needed.',
          code: yaml,
          from_global: true,
        }),
      ];

      render(<MessageList messages={messages} />);

      expect(
        screen.queryByTestId('workflow-diff-blocks')
      ).not.toBeInTheDocument();
    });

    it('renders no diff blocks for non-global assistant messages with code', () => {
      const messages = [
        createMockAIMessage({
          id: 'msg-user',
          role: 'user',
          content: 'Fix my job code',
          code: workflowYaml('fn(state => state);'),
        }),
        createMockAIMessage({
          id: 'msg-job',
          role: 'assistant',
          content: 'Here is the code.',
          code: 'fn(state => state.data);',
          job_id: 'job-1',
        }),
      ];

      render(<MessageList messages={messages} />);

      expect(
        screen.queryByTestId('workflow-diff-blocks')
      ).not.toBeInTheDocument();
    });

    it('opens a changed step in the IDE from its diff block', async () => {
      const onOpenStep = vi.fn();
      const messages = [
        createMockAIMessage({
          id: 'msg-user',
          role: 'user',
          content: 'Change the transform',
          code: workflowYaml('fn(state => state);'),
        }),
        createMockAIMessage({
          id: 'msg-global',
          role: 'assistant',
          content: 'Done.',
          code: workflowYaml('fn(state => state.data);'),
          from_global: true,
        }),
      ];

      render(<MessageList messages={messages} onOpenStep={onOpenStep} />);

      await userEvent.click(screen.getByTestId('diff-block-open-step'));

      // Carries both: the id can be one the parser invented, so the caller
      // resolves by id first and falls back to the name.
      expect(onOpenStep).toHaveBeenCalledWith({
        jobId: 'job-1',
        name: 'Transform data',
      });
    });

    it('offers no link for a removed step, which has nowhere to go', () => {
      const before = twoStepYaml('fn(s => s);', 'fn(s => s);');
      const messages = [
        createMockAIMessage({
          id: 'msg-user',
          role: 'user',
          content: 'Drop the second step',
          code: before,
        }),
        createMockAIMessage({
          id: 'msg-global',
          role: 'assistant',
          content: 'Removed it.',
          code: workflowYaml('fn(s => s);'),
          from_global: true,
        }),
      ];

      render(<MessageList messages={messages} onOpenStep={vi.fn()} />);

      const headers = screen
        .getAllByTestId('diff-block-header')
        .map(h => h.textContent);
      expect(headers.some(h => h?.startsWith('Remove('))).toBe(true);
      // One block is a removal, so there are fewer links than blocks
      expect(
        screen.queryAllByTestId('diff-block-open-step').length
      ).toBeLessThan(screen.getAllByTestId('diff-block').length);
    });

    it('shows no link when navigation is not wired up', () => {
      const messages = [
        createMockAIMessage({
          id: 'msg-user',
          role: 'user',
          content: 'Change it',
          code: workflowYaml('fn(state => state);'),
        }),
        createMockAIMessage({
          id: 'msg-global',
          role: 'assistant',
          content: 'Done.',
          code: workflowYaml('fn(state => state.data);'),
          from_global: true,
        }),
      ];

      render(<MessageList messages={messages} />);

      expect(
        screen.queryByTestId('diff-block-open-step')
      ).not.toBeInTheDocument();
    });

    it('collapses an expanded add block on toggle click', async () => {
      const messages = [
        createMockAIMessage({
          id: 'msg-user',
          role: 'user',
          content: 'Build me a workflow',
        }),
        createMockAIMessage({
          id: 'msg-global',
          role: 'assistant',
          content: 'Here you go.',
          code: workflowYaml('fn(state => state);'),
          from_global: true,
        }),
      ];

      render(<MessageList messages={messages} />);

      // Blocks start expanded, so the toggle collapses rather than expands
      expect(screen.getByTestId('diff-line-added')).toHaveTextContent(
        'fn(state => state);'
      );

      const toggles = screen.getAllByTestId('diff-block-toggle');
      // First toggle belongs to the Add step block
      await userEvent.click(toggles[0]!);
      expect(screen.queryByTestId('diff-line-added')).not.toBeInTheDocument();
    });

    describe('interleaved with response segments', () => {
      it('renders both mentioned step diffs right after the write status row, not at the end', () => {
        const messages = [
          createMockAIMessage({
            id: 'msg-user',
            role: 'user',
            content: 'Update both steps',
            code: twoStepYaml('fn(state => state);', 'sendEmail();'),
          }),
          createMockAIMessage({
            id: 'msg-global',
            role: 'assistant',
            content: 'All done.',
            code: twoStepYaml('fn(state => state.data);', 'sendEmail(body);'),
            from_global: true,
            response_segments: [
              { type: 'text', content: 'Let me update those steps.' },
              {
                type: 'status',
                content: 'Wrote code for "Transform data", "Send to Gmail"',
                summary: 'Wrote code for 2 steps',
                steps: [
                  { key: 'transform-data', name: 'Transform data' },
                  { key: 'send-to-gmail', name: 'Send to Gmail' },
                ],
              },
              { type: 'text', content: 'All done.' },
            ],
          }),
        ];

        render(<MessageList messages={messages} />);

        // Both diffs live in the inline container after the status row
        const inline = screen.getByTestId('status-step-diffs');
        const headers = within(inline).getAllByTestId('diff-block-header');
        expect(headers).toHaveLength(2);
        expect(headers[0]).toHaveTextContent('Update(Transform data)');
        expect(headers[1]).toHaveTextContent('Update(Send to Gmail)');

        // ...immediately after the status row that announced the writes
        const statusRow = screen.getByTestId('settled-status');
        expect(statusRow.nextElementSibling).toBe(inline);

        // Nothing left over for the end of the message
        expect(
          screen.queryByTestId('workflow-diff-blocks')
        ).not.toBeInTheDocument();
      });

      it('does not attach diffs to read-only statuses like "Read code for X"', () => {
        const messages = [
          createMockAIMessage({
            id: 'msg-user',
            role: 'user',
            content: 'Update the transform',
            code: twoStepYaml('fn(state => state);', 'sendEmail();'),
          }),
          createMockAIMessage({
            id: 'msg-global',
            role: 'assistant',
            content: 'Done.',
            code: twoStepYaml('fn(state => state.data);', 'sendEmail();'),
            from_global: true,
            response_segments: [
              { type: 'status', content: 'Read code for "Transform data"' },
              { type: 'text', content: 'Done.' },
            ],
          }),
        ];

        render(<MessageList messages={messages} />);

        // The read status attracts nothing; the diff falls to the end
        expect(
          screen.queryByTestId('status-step-diffs')
        ).not.toBeInTheDocument();
        const tail = screen.getByTestId('workflow-diff-blocks');
        expect(within(tail).getByTestId('diff-block-header')).toHaveTextContent(
          'Update(Transform data)'
        );
      });

      it('renders diffs no status mentioned at the end of the message', () => {
        const messages = [
          createMockAIMessage({
            id: 'msg-user',
            role: 'user',
            content: 'Update both steps',
            code: twoStepYaml('fn(state => state);', 'sendEmail();'),
          }),
          createMockAIMessage({
            id: 'msg-global',
            role: 'assistant',
            content: 'Done.',
            code: twoStepYaml('fn(state => state.data);', 'sendEmail(body);'),
            from_global: true,
            response_segments: [
              {
                type: 'status',
                content: 'Wrote code for "Transform data"',
                steps: [{ key: 'transform-data', name: 'Transform data' }],
              },
              { type: 'text', content: 'Done.' },
            ],
          }),
        ];

        render(<MessageList messages={messages} />);

        // Mentioned step renders inline...
        const inline = screen.getByTestId('status-step-diffs');
        expect(
          within(inline).getByTestId('diff-block-header')
        ).toHaveTextContent('Update(Transform data)');

        // ...the unmentioned one falls to the end
        const tail = screen.getByTestId('workflow-diff-blocks');
        expect(within(tail).getByTestId('diff-block-header')).toHaveTextContent(
          'Update(Send to Gmail)'
        );
      });
    });

    it('keeps the Generated Workflow panel for non-global assistant messages', () => {
      const messages = [
        createMockAIMessage({
          id: 'msg-template',
          role: 'assistant',
          content: 'Here is a workflow.',
          code: workflowYaml('fn(state => state);'),
          // no from_global: workflow-template chat message
        }),
      ];

      render(<MessageList messages={messages} />);

      expect(screen.getByText('Generated Workflow')).toBeInTheDocument();
      expect(screen.getByTestId('expand-code-button')).toBeInTheDocument();
      // No diff blocks either — this is not a global reply
      expect(
        screen.queryByTestId('workflow-diff-blocks')
      ).not.toBeInTheDocument();
    });
  });

  describe('Response Segments Timeline', () => {
    it('renders text blocks and settled status rows in segment order', () => {
      const messages = [
        createMockAIMessage({
          role: 'assistant',
          content: 'Final answer',
          response_segments: [
            { type: 'text', content: 'Adding a step first.' },
            { type: 'status', content: 'Adding step send-to-gmail...' },
            { type: 'text', content: 'Final answer' },
            { type: 'status', content: 'Validating workflow...' },
          ],
        }),
      ];

      render(<MessageList messages={messages} />);

      const assistantMessage = screen.getByTestId('assistant-message');

      // Statuses render settled: italic gray rows, no bouncing dots
      const statusRows = screen.getAllByTestId('settled-status');
      expect(statusRows).toHaveLength(2);
      expect(statusRows[0]).toHaveTextContent('Adding step send-to-gmail...');
      expect(statusRows[1]).toHaveTextContent('Validating workflow...');
      statusRows.forEach(row => {
        expect(row.querySelector('.animate-bounce')).not.toBeInTheDocument();
        expect(row.querySelector('.italic')).toBeInTheDocument();
      });

      // Both text segments render (not the joined flat content once)
      expect(screen.getByText('Adding a step first.')).toBeInTheDocument();
      expect(screen.getByText('Final answer')).toBeInTheDocument();

      // DOM order matches segment order: text, status, text, status
      const textContent = assistantMessage.textContent ?? '';
      expect(textContent.indexOf('Adding a step first.')).toBeLessThan(
        textContent.indexOf('Adding step send-to-gmail...')
      );
      expect(textContent.indexOf('Adding step send-to-gmail...')).toBeLessThan(
        textContent.indexOf('Final answer')
      );
      expect(textContent.indexOf('Final answer')).toBeLessThan(
        textContent.indexOf('Validating workflow...')
      );
    });

    it('renders flat content when response_segments is absent or empty', () => {
      const messages = [
        createMockAIMessage({
          id: '1',
          role: 'assistant',
          content: 'Legacy flat message',
        }),
        createMockAIMessage({
          id: '2',
          role: 'assistant',
          content: 'Empty segments message',
          response_segments: [],
        }),
      ];

      render(<MessageList messages={messages} />);

      expect(screen.getByText('Legacy flat message')).toBeInTheDocument();
      expect(screen.getByText('Empty segments message')).toBeInTheDocument();
      expect(screen.queryByTestId('settled-status')).not.toBeInTheDocument();
    });

    it('settles timeline statuses with ticks and shows the thinking scalar with dots (global active)', () => {
      const messages = [
        createMockAIMessage({ role: 'user', content: 'Question' }),
      ];

      const { rerender } = render(
        <MessageList
          messages={messages}
          isLoading
          isGlobalAssistantActive
          streamingContent="Answer"
          streamingStatus="Writing the next step..."
          streamingSegments={[
            { type: 'status', content: 'Edited workflow structure' },
            { type: 'text', content: 'Answer' },
            { type: 'status', content: 'Added step send-to-gmail' },
          ]}
        />
      );

      // Timeline statuses are completed actions: settled + tick, even the
      // trailing one, even mid-stream.
      const settled = screen.getAllByTestId('settled-status');
      expect(settled).toHaveLength(2);
      for (const row of settled) {
        expect(row.querySelector('.animate-bounce')).not.toBeInTheDocument();
        expect(row.querySelector('.hero-check-micro')).toBeInTheDocument();
      }

      // The transient thinking status renders below with dots.
      const thinking = screen.getByTestId('streaming-status');
      expect(thinking).toHaveTextContent('Writing the next step...');
      expect(thinking.querySelectorAll('.animate-bounce')).toHaveLength(3);

      // No thinking scalar → no dots row at all.
      rerender(
        <MessageList
          messages={messages}
          isLoading
          isGlobalAssistantActive
          streamingContent="Answer"
          streamingStatus={null}
          streamingSegments={[
            { type: 'status', content: 'Edited workflow structure' },
            { type: 'text', content: 'Answer' },
          ]}
        />
      );
      expect(screen.queryByTestId('streaming-status')).not.toBeInTheDocument();
      expect(screen.getByTestId('settled-status')).toHaveTextContent(
        'Edited workflow structure'
      );
    });

    it('shows a leading status segment before any text has streamed', () => {
      // Apollo can complete an action (and emit its status) before the
      // first text chunk arrives; the streaming placeholder must render
      // from segments alone.
      const messages = [
        createMockAIMessage({ role: 'user', content: 'Question' }),
      ];

      render(
        <MessageList
          messages={messages}
          isLoading
          isGlobalAssistantActive
          streamingContent={null}
          streamingStatus={null}
          streamingSegments={[
            { type: 'status', content: 'Edited workflow structure' },
          ]}
        />
      );

      expect(screen.getByTestId('streaming-message')).toBeInTheDocument();
      expect(screen.getByTestId('settled-status')).toHaveTextContent(
        'Edited workflow structure'
      );
    });

    it('keeps flat streaming rendering when the global assistant is not active', () => {
      const messages = [
        createMockAIMessage({ role: 'user', content: 'Question' }),
      ];

      render(
        <MessageList
          messages={messages}
          isLoading
          streamingContent="Flat answer"
          streamingStatus="Generating code..."
          streamingSegments={[
            { type: 'text', content: 'Flat answer' },
            { type: 'status', content: 'Generating code...' },
          ]}
        />
      );

      // Flat content + single scalar status row, no woven timeline
      expect(screen.getByText('Flat answer')).toBeInTheDocument();
      expect(screen.queryByTestId('settled-status')).not.toBeInTheDocument();
      const status = screen.getByTestId('streaming-status');
      expect(status).toHaveTextContent('Generating code...');
      expect(status.querySelectorAll('.animate-bounce')).toHaveLength(3);
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
