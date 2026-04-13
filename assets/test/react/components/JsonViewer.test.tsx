/**
 * JsonViewer Tests
 *
 * Verifies JsonViewer behaviour:
 * - Renders Monaco with the provided content string
 * - Copy button copies `content` when no `copyContent` prop is given
 * - Copy button copies `copyContent` when provided (not the displayed content)
 * - Copy button toggles to checkmark on click, reverts after 2s
 * - Copy button is absent when content is empty or 'Failed to load content'
 */

import { act, render, screen } from '@testing-library/react';
import { fireEvent } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { JsonViewer } from '../../../js/react/components/JsonViewer';

// Mock @monaco-editor/react so tests don't load the full 8MB package.
vi.mock('@monaco-editor/react', () => ({
  default: ({ value }: { value?: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
  loader: { config: () => {} },
}));

// Mock the #/monaco module which wraps @monaco-editor/react with resize
// observer and theme logic — JsonViewer imports MonacoEditor from here.
vi.mock('../../../js/monaco', () => ({
  MonacoEditor: ({ value }: { value?: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
}));

// =============================================================================
// CLIPBOARD HELPERS
// =============================================================================

function createMockClipboard() {
  const writeText = vi.fn().mockResolvedValue(undefined);
  return { writeText };
}

// =============================================================================
// TESTS
// =============================================================================

describe('JsonViewer', () => {
  let mockClipboard: { writeText: ReturnType<typeof vi.fn> };

  beforeEach(() => {
    mockClipboard = createMockClipboard();
    Object.defineProperty(navigator, 'clipboard', {
      value: mockClipboard,
      configurable: true,
      writable: true,
    });
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
  });

  // ===========================================================================
  // RENDERING
  // ===========================================================================

  describe('rendering', () => {
    test('renders Monaco editor with the provided content', () => {
      const content = '{"key": "value"}';
      render(<JsonViewer content={content} />);

      const editor = screen.getByTestId('monaco-editor');
      expect(editor).toBeInTheDocument();
      expect(editor).toHaveTextContent(content);
    });

    test('renders copy button when content is non-empty and not an error', () => {
      render(<JsonViewer content='{"ok": true}' />);

      expect(
        screen.getByRole('button', { name: 'Copy to clipboard' })
      ).toBeInTheDocument();
    });

    test('does not render copy button when content is empty string', () => {
      render(<JsonViewer content="" />);

      expect(
        screen.queryByRole('button', { name: /copy/i })
      ).not.toBeInTheDocument();
    });

    test('does not render copy button when content is the error sentinel', () => {
      render(<JsonViewer content="Failed to load content" />);

      expect(
        screen.queryByRole('button', { name: /copy/i })
      ).not.toBeInTheDocument();
    });
  });

  // ===========================================================================
  // COPY BEHAVIOUR
  // ===========================================================================

  describe('copy behaviour', () => {
    test('copies content to clipboard when no copyContent prop is given', async () => {
      const content = '{"hello": "world"}';
      render(<JsonViewer content={content} />);

      const button = screen.getByRole('button', {
        name: 'Copy to clipboard',
      });

      // Use fireEvent to avoid userEvent timeout issues with fake timers
      await act(async () => {
        fireEvent.click(button);
        // Allow microtasks (the clipboard.writeText promise) to settle
        await Promise.resolve();
      });

      expect(mockClipboard.writeText).toHaveBeenCalledWith(content);
    });

    test('copies copyContent when provided, not the displayed content', async () => {
      const displayContent = '{"short": "display"}';
      const originalContent = '{"full": "original long content"}';
      render(
        <JsonViewer content={displayContent} copyContent={originalContent} />
      );

      const button = screen.getByRole('button', {
        name: 'Copy to clipboard',
      });

      await act(async () => {
        fireEvent.click(button);
        await Promise.resolve();
      });

      expect(mockClipboard.writeText).toHaveBeenCalledWith(originalContent);
      expect(mockClipboard.writeText).not.toHaveBeenCalledWith(displayContent);
    });
  });

  // ===========================================================================
  // COPY BUTTON STATE TRANSITIONS
  // ===========================================================================

  describe('copy button state', () => {
    test('button shows checkmark after click and reverts after 2s', async () => {
      render(<JsonViewer content='{"x": 1}' />);

      const button = screen.getByRole('button', {
        name: 'Copy to clipboard',
      });

      await act(async () => {
        fireEvent.click(button);
        // Let the clipboard.writeText promise resolve and setState run
        await Promise.resolve();
        await Promise.resolve();
      });

      // After click: aria-label should change to "Copied to clipboard"
      expect(
        screen.getByRole('button', { name: 'Copied to clipboard' })
      ).toBeInTheDocument();

      // Advance 2 seconds — button should revert
      act(() => {
        vi.advanceTimersByTime(2000);
      });

      expect(
        screen.getByRole('button', { name: 'Copy to clipboard' })
      ).toBeInTheDocument();
    });
  });
});
