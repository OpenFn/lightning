/**
 * CollectionPreviewViewer Tests
 *
 * Verifies CollectionPreviewViewer behaviour:
 * - Truncates string values > 140 chars in the displayed JSON with …
 * - Passes the original untruncated JSON as copyContent to CodeViewer
 * - Handles nested objects and arrays recursively
 * - Non-string values (numbers, booleans, null) pass through unchanged
 * - Renders as-is when json is not valid JSON
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { CollectionPreviewViewer } from '../../../js/react/components/CollectionPreviewViewer';

// Mock @monaco-editor/react so tests don't load the full 8MB package.
vi.mock('@monaco-editor/react', () => ({
  default: ({ value }: { value?: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
  loader: { config: () => {} },
}));

// Mock the #/monaco module which wraps @monaco-editor/react with resize
// observer and theme logic.
vi.mock('../../../js/monaco', () => ({
  MonacoEditor: ({ value }: { value?: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
}));

// =============================================================================
// HELPERS
// =============================================================================

const SHORT = 'short value';
const LONG = 'a'.repeat(141); // 141 chars — one over the 140 limit
const TRUNCATED = 'a'.repeat(140) + '\u2026'; // expected truncated form

function createMockClipboard() {
  const writeText = vi.fn().mockResolvedValue(undefined);
  return { writeText };
}

// =============================================================================
// TESTS
// =============================================================================

describe('CollectionPreviewViewer', () => {
  let mockClipboard: { writeText: ReturnType<typeof vi.fn> };

  beforeEach(() => {
    mockClipboard = createMockClipboard();
    Object.defineProperty(navigator, 'clipboard', {
      value: mockClipboard,
      configurable: true,
      writable: true,
    });
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  // ===========================================================================
  // STRING TRUNCATION
  // ===========================================================================

  describe('string truncation in display', () => {
    test('truncates string values longer than 140 chars with ellipsis', () => {
      const json = JSON.stringify({ value: LONG });
      render(<CollectionPreviewViewer json={json} />);

      const editorText = screen.getByTestId('monaco-editor').textContent;
      expect(editorText).toContain(TRUNCATED);
      expect(editorText).not.toContain(LONG);
    });

    test('does not truncate string values of exactly 140 chars', () => {
      const exact = 'b'.repeat(140);
      const json = JSON.stringify({ value: exact });
      render(<CollectionPreviewViewer json={json} />);

      const editorText = screen.getByTestId('monaco-editor').textContent;
      expect(editorText).toContain(exact);
      expect(editorText).not.toContain('\u2026');
    });

    test('does not truncate short string values', () => {
      const json = JSON.stringify({ value: SHORT });
      render(<CollectionPreviewViewer json={json} />);

      const editorText = screen.getByTestId('monaco-editor').textContent;
      expect(editorText).toContain(SHORT);
    });
  });

  // ===========================================================================
  // COPY CONTENT PASSES ORIGINAL JSON
  // ===========================================================================

  describe('copy button copies original untruncated JSON', () => {
    test('clipboard receives the full original json, not the truncated display', async () => {
      const json = JSON.stringify({ value: LONG });
      render(<CollectionPreviewViewer json={json} />);

      await userEvent.click(
        screen.getByRole('button', { name: 'Copy to clipboard' })
      );

      expect(mockClipboard.writeText).toHaveBeenCalledWith(json);
      // Confirm it did NOT copy the truncated version
      expect(mockClipboard.writeText).not.toHaveBeenCalledWith(
        expect.stringContaining(TRUNCATED)
      );
    });
  });

  // ===========================================================================
  // RECURSIVE TRUNCATION
  // ===========================================================================

  describe('recursive truncation', () => {
    test('truncates strings nested inside objects', () => {
      const json = JSON.stringify({
        outer: { inner: LONG },
      });
      render(<CollectionPreviewViewer json={json} />);

      const editorText = screen.getByTestId('monaco-editor').textContent;
      expect(editorText).toContain(TRUNCATED);
    });

    test('truncates strings nested inside arrays', () => {
      const json = JSON.stringify([LONG, SHORT]);
      render(<CollectionPreviewViewer json={json} />);

      const editorText = screen.getByTestId('monaco-editor').textContent;
      expect(editorText).toContain(TRUNCATED);
      expect(editorText).toContain(SHORT);
    });

    test('truncates strings at multiple levels of nesting', () => {
      const json = JSON.stringify({
        level1: { level2: [{ level3: LONG }] },
      });
      render(<CollectionPreviewViewer json={json} />);

      const editorText = screen.getByTestId('monaco-editor').textContent;
      expect(editorText).toContain(TRUNCATED);
    });
  });

  // ===========================================================================
  // NON-STRING PASS-THROUGH
  // ===========================================================================

  describe('non-string value pass-through', () => {
    test('numbers, booleans, and null are not modified', () => {
      const json = JSON.stringify({
        count: 42,
        active: true,
        nothing: null,
      });
      render(<CollectionPreviewViewer json={json} />);

      const editorText = screen.getByTestId('monaco-editor').textContent;
      expect(editorText).toContain('42');
      expect(editorText).toContain('true');
      expect(editorText).toContain('null');
    });
  });

  // ===========================================================================
  // INVALID JSON HANDLING
  // ===========================================================================

  describe('invalid JSON handling', () => {
    test('renders the raw string as-is when json is not valid JSON', () => {
      const invalid = 'not valid json {{';
      render(<CollectionPreviewViewer json={invalid} />);

      const editorText = screen.getByTestId('monaco-editor').textContent;
      expect(editorText).toContain(invalid);
    });
  });
});
