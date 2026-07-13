/**
 * TemplateBrowserModalWrapper - creation-flow save handling
 *
 * Covers the connectivity gate, import, and save wiring around
 * `handleSelect` in `TemplateBrowserModalWrapper.tsx`. Save-failure feedback
 * itself is owned by the shared handler in `useWorkflow.tsx` (mocked out
 * here via `useWorkflowActions`), so this file only asserts this component's
 * own responsibilities: gating, calling import/save with the right options,
 * and resetting local pending state.
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { TemplateBrowserModalWrapper } from '../../../js/collaborative-editor/components/TemplateBrowserModalWrapper';
import { notifications } from '../../../js/collaborative-editor/lib/notifications';

const mockAlert = vi.mocked(notifications.alert);

// --- Session (workflow-session socket connectivity) ---

let mockIsConnected = true;
vi.mock('../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: (
    selector: (s: { provider: null; isConnected: boolean }) => unknown
  ) => selector({ provider: null, isConnected: mockIsConnected }),
}));

// --- Workflow actions ---

const mockImportWorkflow = vi.fn().mockResolvedValue(undefined);
const mockSaveWorkflow = vi.fn().mockResolvedValue({ ok: true });

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowActions: () => ({
    importWorkflow: mockImportWorkflow,
    saveWorkflow: mockSaveWorkflow,
  }),
}));

// --- UI store ---

const mockCloseTemplateBrowserModal = vi.fn();
const mockDismissLandingScreen = vi.fn();

vi.mock('../../../js/collaborative-editor/hooks/useUI', () => ({
  useShowTemplateBrowserModal: () => true,
  useUICommands: () => ({
    closeTemplateBrowserModal: mockCloseTemplateBrowserModal,
    dismissLandingScreen: mockDismissLandingScreen,
  }),
}));

// --- Templates API (channel is null in this test, so it's never called;
// mocked defensively per the shared pattern) ---

vi.mock('../../../js/collaborative-editor/api/templates', () => ({
  fetchTemplates: vi.fn().mockResolvedValue([]),
}));

// --- Notifications ---

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

function renderWrapper() {
  return render(<TemplateBrowserModalWrapper />);
}

async function clickFirstTemplate() {
  const user = userEvent.setup();
  const card = await screen.findByRole('button', {
    name: /Event-based workflow/i,
  });
  await user.click(card);
  return card;
}

describe('TemplateBrowserModalWrapper', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsConnected = true;
    mockImportWorkflow.mockResolvedValue(undefined);
    mockSaveWorkflow.mockResolvedValue({ ok: true });
  });

  test('success: imports, saves with notify: error-only, closes the modal, and dismisses the landing screen', async () => {
    renderWrapper();

    await clickFirstTemplate();

    await waitFor(() => {
      expect(mockImportWorkflow).toHaveBeenCalledOnce();
      expect(mockSaveWorkflow).toHaveBeenCalledWith({ notify: 'error-only' });
      expect(mockCloseTemplateBrowserModal).toHaveBeenCalledOnce();
      expect(mockDismissLandingScreen).toHaveBeenCalledOnce();
    });

    const importOrder = mockImportWorkflow.mock.invocationCallOrder[0];
    const saveOrder = mockSaveWorkflow.mock.invocationCallOrder[0];
    expect(importOrder).toBeLessThan(saveOrder);
  });

  test('save rejection: modal stays open, no bespoke alert, and the card is re-enabled', async () => {
    mockSaveWorkflow.mockRejectedValue(new Error('boom'));
    renderWrapper();

    const card = await clickFirstTemplate();

    await waitFor(() => {
      expect(mockSaveWorkflow).toHaveBeenCalledWith({ notify: 'error-only' });
    });

    expect(mockCloseTemplateBrowserModal).not.toHaveBeenCalled();
    expect(mockDismissLandingScreen).not.toHaveBeenCalled();
    // The shared save handler (mocked out via useWorkflowActions) owns the
    // Retry toast; this component shows no alert of its own for save failures.
    expect(mockAlert).not.toHaveBeenCalled();

    await waitFor(() => {
      expect(card).not.toBeDisabled();
    });
  });

  test('offline gate: shows a "Not connected" alert and never touches the doc', async () => {
    mockIsConnected = false;
    renderWrapper();

    await clickFirstTemplate();

    await waitFor(() => {
      expect(mockAlert).toHaveBeenCalledWith({
        title: 'Not connected',
        description: 'Connection lost — please wait a moment and try again.',
      });
    });

    expect(mockImportWorkflow).not.toHaveBeenCalled();
    expect(mockSaveWorkflow).not.toHaveBeenCalled();
    expect(mockCloseTemplateBrowserModal).not.toHaveBeenCalled();
  });
});
