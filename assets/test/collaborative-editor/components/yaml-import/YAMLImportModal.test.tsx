import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { describe, expect, test, vi, beforeEach } from 'vitest';

import { YAMLImportModal } from '../../../../js/collaborative-editor/components/YAMLImportModal';
import { notifications } from '../../../../js/collaborative-editor/lib/notifications';

const mockNotificationsAlert = vi.mocked(notifications.alert);

// --- Workflow mocks ---

const mockImportWorkflow = vi.fn().mockResolvedValue(undefined);
const mockSaveWorkflow = vi.fn().mockResolvedValue({ ok: true });

// `useCreateWorkflowFlow` is re-implemented here (mirroring the real gate/
// import/save sequence in useWorkflow.tsx) rather than mocked-through, since
// it lives in the same module as `useWorkflowActions` and a vi.mock override
// of one export can't reach an internal same-module call to the other.
vi.mock('../../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowActions: () => ({
    importWorkflow: mockImportWorkflow,
    saveWorkflow: mockSaveWorkflow,
  }),
  useCreateWorkflowFlow: () => ({
    createWorkflowFrom: async (buildState: () => unknown) => {
      if (!mockIsConnected) {
        mockNotificationsAlert({
          title: 'Not connected',
          description: 'Connect to the server before creating a workflow.',
        });
        return false;
      }
      try {
        const state = buildState();
        await mockImportWorkflow(state);
      } catch {
        mockNotificationsAlert({
          title: 'Failed to create workflow',
          description: 'Please check your connection and try again.',
        });
        return false;
      }
      try {
        await mockSaveWorkflow({ notify: 'error-only' });
      } catch {
        return false;
      }
      return true;
    },
  }),
}));

let mockIsConnected = true;
vi.mock('../../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: (selector: (s: { isConnected: boolean }) => unknown) =>
    selector({ isConnected: mockIsConnected }),
}));

vi.mock('../../../../js/collaborative-editor/lib/notifications', () => ({
  notifications: {
    alert: vi.fn(),
    success: vi.fn(),
    dismiss: vi.fn(),
  },
}));

// --- UI mocks ---

const mockCloseYAMLImportModal = vi.fn();
const mockDismissLandingScreen = vi.fn();
const mockShowYAMLImportModal = vi.fn();
const mockImportPanelState = vi.fn();

// Wired so that calling setImportState updates what useImportPanelState returns,
// matching how the real store works (write → read reflects the change on re-render).
const mockSetImportState = vi.fn((state: string) => {
  mockImportPanelState.mockReturnValue(state);
});

vi.mock('../../../../js/collaborative-editor/hooks/useUI', () => ({
  useUICommands: () => ({
    closeYAMLImportModal: mockCloseYAMLImportModal,
    dismissLandingScreen: mockDismissLandingScreen,
    setImportState: mockSetImportState,
    setImportYamlContent: vi.fn(),
  }),
  useShowYAMLImportModal: () => mockShowYAMLImportModal(),
  useImportPanelState: () => mockImportPanelState(),
  useImportYamlContent: () => '',
}));

vi.mock('../../../../js/collaborative-editor/keyboard', () => ({
  useKeyboardShortcut: vi.fn(),
}));

// --- Fixtures ---

const validYAML = `
name: Test Workflow
jobs:
  test-job:
    name: Test Job
    adaptor: '@openfn/language-http@latest'
    body: |
      get('/api/data')
triggers:
  webhook:
    type: webhook
    enabled: true
edges:
  webhook->test-job:
    source_trigger: webhook
    target_job: test-job
    condition_type: always
    enabled: true
`;

function renderModal() {
  return render(<YAMLImportModal />);
}

function switchToPasteMode() {
  fireEvent.click(screen.getByRole('button', { name: /Paste text/i }));
}

function enterYAML(content: string) {
  fireEvent.change(
    screen.getByPlaceholderText(/Paste your YAML content here/i),
    {
      target: { value: content },
    }
  );
}

// --- Tests ---

describe('YAMLImportModal', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockShowYAMLImportModal.mockReturnValue(true);
    mockImportPanelState.mockReturnValue('initial');
    mockIsConnected = true;
    mockImportWorkflow.mockResolvedValue(undefined);
    mockSaveWorkflow.mockResolvedValue({ ok: true });
  });

  describe('Modal visibility', () => {
    test('renders dialog content when open', () => {
      renderModal();

      expect(screen.getByText(/Import a workflow/i)).toBeInTheDocument();
      expect(
        screen.getByRole('button', { name: /Cancel/i })
      ).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /Create/i })).toBeDisabled();
      expect(
        screen.getByRole('button', { name: /Paste text/i })
      ).toBeInTheDocument();
      expect(
        screen.getByText(/Upload or drop a YAML file/i)
      ).toBeInTheDocument();
    });

    test('renders nothing when closed', () => {
      mockShowYAMLImportModal.mockReturnValue(false);
      renderModal();

      expect(screen.queryByText(/Import a workflow/i)).not.toBeInTheDocument();
    });
  });

  describe('Cancel', () => {
    test('clicking Cancel calls closeYAMLImportModal', () => {
      renderModal();

      fireEvent.click(screen.getByRole('button', { name: /Cancel/i }));

      expect(mockCloseYAMLImportModal).toHaveBeenCalledOnce();
    });
  });

  describe('Mode toggle', () => {
    test('switches between upload and paste modes', () => {
      renderModal();

      switchToPasteMode();
      expect(
        screen.queryByText(/Upload or drop a YAML file/i)
      ).not.toBeInTheDocument();
      expect(
        screen.getByRole('button', { name: /Upload a file/i })
      ).toBeInTheDocument();

      fireEvent.click(screen.getByRole('button', { name: /Upload a file/i }));
      expect(
        screen.getByText(/Upload or drop a YAML file/i)
      ).toBeInTheDocument();
      expect(
        screen.getByRole('button', { name: /Paste text/i })
      ).toBeInTheDocument();
    });
  });

  describe('YAML validation', () => {
    test('enables Create after valid YAML is entered', async () => {
      renderModal();
      switchToPasteMode();
      enterYAML(validYAML);

      await waitFor(
        () =>
          expect(
            screen.getByRole('button', { name: /Create/i })
          ).not.toBeDisabled(),
        { timeout: 500 }
      );
    });

    test('keeps Create disabled for invalid YAML', async () => {
      renderModal();
      switchToPasteMode();
      enterYAML('invalid: [syntax');

      await waitFor(
        () =>
          expect(
            screen.getByRole('button', { name: /Create/i })
          ).toBeDisabled(),
        { timeout: 500 }
      );
    });
  });

  describe('Import flow', () => {
    test('on success: imports, saves, closes modal, and dismisses landing screen', async () => {
      renderModal();
      switchToPasteMode();
      enterYAML(validYAML);

      await waitFor(
        () =>
          expect(
            screen.getByRole('button', { name: /Create/i })
          ).not.toBeDisabled(),
        { timeout: 500 }
      );

      fireEvent.click(screen.getByRole('button', { name: /Create/i }));

      await waitFor(() => {
        expect(mockImportWorkflow).toHaveBeenCalledOnce();
        expect(mockSaveWorkflow).toHaveBeenCalledWith({
          notify: 'error-only',
        });
        expect(mockCloseYAMLImportModal).toHaveBeenCalledOnce();
        expect(mockDismissLandingScreen).toHaveBeenCalledOnce();
      });
    });

    test('on failure: keeps modal open and does not dismiss landing screen', async () => {
      mockImportWorkflow.mockRejectedValue(new Error('network error'));
      renderModal();
      switchToPasteMode();
      enterYAML(validYAML);

      await waitFor(
        () =>
          expect(
            screen.getByRole('button', { name: /Create/i })
          ).not.toBeDisabled(),
        { timeout: 500 }
      );

      fireEvent.click(screen.getByRole('button', { name: /Create/i }));

      await waitFor(() => {
        expect(mockCloseYAMLImportModal).not.toHaveBeenCalled();
        expect(mockDismissLandingScreen).not.toHaveBeenCalled();
      });
    });

    test('offline gate: shows Not connected and skips import', async () => {
      mockIsConnected = false;
      renderModal();
      switchToPasteMode();
      enterYAML(validYAML);

      await waitFor(
        () =>
          expect(
            screen.getByRole('button', { name: /Create/i })
          ).not.toBeDisabled(),
        { timeout: 500 }
      );

      fireEvent.click(screen.getByRole('button', { name: /Create/i }));

      await waitFor(() => {
        expect(mockNotificationsAlert).toHaveBeenCalledWith({
          title: 'Not connected',
          description: 'Connect to the server before creating a workflow.',
        });
      });
      expect(mockImportWorkflow).not.toHaveBeenCalled();
      expect(mockCloseYAMLImportModal).not.toHaveBeenCalled();
    });

    test('save failure: keeps modal open, re-enables Create, and shows no bespoke alert', async () => {
      mockSaveWorkflow.mockRejectedValue(new Error('boom'));
      renderModal();
      switchToPasteMode();
      enterYAML(validYAML);

      await waitFor(
        () =>
          expect(
            screen.getByRole('button', { name: /Create/i })
          ).not.toBeDisabled(),
        { timeout: 500 }
      );

      fireEvent.click(screen.getByRole('button', { name: /Create/i }));

      await waitFor(() => {
        expect(mockSaveWorkflow).toHaveBeenCalledWith({
          notify: 'error-only',
        });
      });
      expect(mockDismissLandingScreen).not.toHaveBeenCalled();
      expect(mockCloseYAMLImportModal).not.toHaveBeenCalled();
      expect(mockNotificationsAlert).not.toHaveBeenCalled();
      expect(mockSetImportState).toHaveBeenCalledWith('importing');
      expect(mockSetImportState).toHaveBeenLastCalledWith('valid');
    });
  });
});
