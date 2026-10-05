/**
 * DataclipViewer Tests
 *
 * Verifies DataclipViewer behaviour:
 * - Fetches /dataclip/body/:id and displays pretty-printed JSON on 200
 * - Renders "Dataclip not found" on 404
 * - Renders "Failed to load content" on network failure (fetch throws)
 * - Renders "Failed to load content" on non-OK responses (e.g. 500)
 */

import { render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { DataclipViewer } from '../../../js/react/components/DataclipViewer';

// Mock Monaco so tests don't load the full 8MB package.
vi.mock('../../../js/monaco', () => ({
  MonacoEditor: ({ value }: { value?: string }) => (
    <div data-testid="monaco-editor">{value}</div>
  ),
}));

// =============================================================================
// HELPERS
// =============================================================================

function mockFetchOk(body: string) {
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      text: () => Promise.resolve(body),
    })
  );
}

function mockFetchStatus(status: number) {
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({
      ok: false,
      status,
      text: () => Promise.resolve(''),
    })
  );
}

function mockFetchThrows(error: Error) {
  vi.stubGlobal('fetch', vi.fn().mockRejectedValue(error));
}

// =============================================================================
// TESTS
// =============================================================================

describe('DataclipViewer', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
  });

  // ===========================================================================
  // HAPPY PATH
  // ===========================================================================

  describe('200 response', () => {
    test('renders pretty-printed JSON content when fetch returns 200', async () => {
      mockFetchOk('{"foo":"bar"}');

      render(<DataclipViewer dataclipId="abc-123" />);

      const editor = await screen.findByTestId('monaco-editor');
      // The component parses and re-stringifies with 2-space indent.
      // toHaveTextContent normalises whitespace, so compare raw textContent.
      expect(editor.textContent).toBe(JSON.stringify({ foo: 'bar' }, null, 2));
    });
  });

  // ===========================================================================
  // 404 — MISSING DATACLIP
  // ===========================================================================

  describe('404 response', () => {
    test('renders "Dataclip not found" when fetch returns 404', async () => {
      mockFetchStatus(404);

      render(<DataclipViewer dataclipId="missing-uuid" />);

      const editor = await screen.findByTestId('monaco-editor');
      // Strict equality (not toHaveTextContent) so a different wording fails.
      expect(editor.textContent).toBe('Dataclip not found');
    });
  });

  // ===========================================================================
  // ERROR FALLBACK
  // ===========================================================================

  describe('error fallback', () => {
    beforeEach(() => {
      // Component logs to console.error on the catch path; suppress to keep
      // test output clean. Restored automatically by clearAllMocks in afterEach.
      vi.spyOn(console, 'error').mockImplementation(() => {});
    });

    test('renders "Failed to load content" when fetch throws a network error', async () => {
      mockFetchThrows(new Error('Network error'));

      render(<DataclipViewer dataclipId="abc-123" />);

      const editor = await screen.findByTestId('monaco-editor');
      expect(editor).toHaveTextContent('Failed to load content');
    });

    test('renders "Failed to load content" when fetch returns 500', async () => {
      mockFetchStatus(500);

      render(<DataclipViewer dataclipId="abc-123" />);

      const editor = await screen.findByTestId('monaco-editor');
      expect(editor).toHaveTextContent('Failed to load content');
    });
  });
});
