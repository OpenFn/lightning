/**
 * TemplateBrowserModalWrapper - template fetch race guard
 *
 * Covers the lazy-fetch effect that loads templates when the modal opens:
 * a stale response from a previous open must never overwrite a newer one.
 */

import { render } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { fetchTemplates } from '../../../js/collaborative-editor/api/templates';
import { TemplateBrowserModalWrapper } from '../../../js/collaborative-editor/components/TemplateBrowserModalWrapper';

const mockFetchTemplates = vi.mocked(fetchTemplates);

// --- Session (provides a truthy channel so the fetch effect runs) ---

vi.mock('../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: (
    selector: (s: {
      provider: { channel: object };
      isConnected: boolean;
    }) => unknown
  ) => selector({ provider: { channel: {} }, isConnected: true }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowActions: () => ({
    importWorkflow: vi.fn(),
    saveWorkflow: vi.fn(),
  }),
  useCreateWorkflowFlow: () => ({
    createWorkflowFrom: vi.fn().mockResolvedValue(true),
  }),
}));

// --- UI store ---

let mockIsOpen = true;
const mockSetTemplates = vi.fn();
const mockSetTemplatesLoading = vi.fn();

vi.mock('../../../js/collaborative-editor/hooks/useUI', () => ({
  useShowTemplateBrowserModal: () => mockIsOpen,
  useTemplatePanel: () => ({
    templates: [],
    loading: false,
    searchQuery: '',
  }),
  useUICommands: () => ({
    closeTemplateBrowserModal: vi.fn(),
    dismissLandingScreen: vi.fn(),
    setTemplates: mockSetTemplates,
    setTemplatesLoading: mockSetTemplatesLoading,
    setTemplateSearchQuery: vi.fn(),
  }),
}));

vi.mock('../../../js/collaborative-editor/api/templates', () => ({
  fetchTemplates: vi.fn(),
}));

vi.mock('../../../js/collaborative-editor/lib/notifications', () => ({
  notifications: {
    alert: vi.fn(),
    success: vi.fn(),
    dismiss: vi.fn(),
  },
}));

vi.mock('../../../js/collaborative-editor/keyboard', () => ({
  useKeyboardShortcut: vi.fn(),
}));

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(_resolve => {
    resolve = _resolve;
  });
  return { promise, resolve };
}

describe('TemplateBrowserModalWrapper - template fetch race guard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsOpen = true;
  });

  test('a stale fetch resolving after a newer one does not overwrite it', async () => {
    const firstFetch = deferred<{ name: string }[]>();
    const secondFetch = deferred<{ name: string }[]>();
    mockFetchTemplates
      .mockReturnValueOnce(firstFetch.promise)
      .mockReturnValueOnce(secondFetch.promise);

    const { rerender } = render(<TemplateBrowserModalWrapper />);
    expect(mockFetchTemplates).toHaveBeenCalledTimes(1);

    // Close before the first fetch resolves, then reopen — this fires a
    // second fetch while the first is still in flight.
    mockIsOpen = false;
    rerender(<TemplateBrowserModalWrapper />);
    mockIsOpen = true;
    rerender(<TemplateBrowserModalWrapper />);
    expect(mockFetchTemplates).toHaveBeenCalledTimes(2);

    // Newer fetch resolves first.
    secondFetch.resolve([{ name: 'Second' }]);
    await vi.waitFor(() => {
      expect(mockSetTemplates).toHaveBeenCalledWith(
        expect.arrayContaining([expect.objectContaining({ name: 'Second' })])
      );
    });

    const callsAfterSecond = mockSetTemplates.mock.calls.length;

    // Stale fetch resolves after — must be ignored, not overwrite the result.
    firstFetch.resolve([{ name: 'First' }]);
    await Promise.resolve();
    await Promise.resolve();

    expect(mockSetTemplates).toHaveBeenCalledTimes(callsAfterSecond);
    expect(mockSetTemplates).not.toHaveBeenCalledWith(
      expect.arrayContaining([expect.objectContaining({ name: 'First' })])
    );
  });
});
