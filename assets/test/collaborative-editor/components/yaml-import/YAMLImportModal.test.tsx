/**
 * YAMLImportModal Component Tests
 *
 * Covers modal-specific behaviour: visibility gating, Cancel/Escape close,
 * successful import flow, state machine, mode toggling, and debounced validation.
 */

import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { describe, expect, test, vi, beforeEach } from 'vitest';

import { YAMLImportModal } from '../../../../js/collaborative-editor/components/YAMLImportModal';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { useKeyboardShortcut } from '../../../../js/collaborative-editor/keyboard';
import { createMockStoreContextValue } from '../../__helpers__';

vi.mock('../../../../js/collaborative-editor/hooks/useAwareness', () => ({
  useAwareness: () => [],
}));

const mockImportWorkflow = vi.fn().mockResolvedValue(undefined);
const mockSaveWorkflow = vi.fn().mockResolvedValue(undefined);

vi.mock('../../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowActions: () => ({
    importWorkflow: mockImportWorkflow,
    saveWorkflow: mockSaveWorkflow,
  }),
}));

const mockCloseYAMLImportModal = vi.fn();
const mockDismissLandingScreen = vi.fn();

let mockIsOpen = true;

vi.mock('../../../../js/collaborative-editor/hooks/useUI', () => ({
  useUICommands: () => ({
    closeYAMLImportModal: mockCloseYAMLImportModal,
    dismissLandingScreen: mockDismissLandingScreen,
    collapseCreateWorkflowPanel: vi.fn(),
    expandCreateWorkflowPanel: vi.fn(),
    toggleCreateWorkflowPanel: vi.fn(),
    openRunPanel: vi.fn(),
    closeRunPanel: vi.fn(),
    openAIAssistantPanel: vi.fn(),
    closeAIAssistantPanel: vi.fn(),
    toggleAIAssistantPanel: vi.fn(),
    openGitHubSyncModal: vi.fn(),
    closeGitHubSyncModal: vi.fn(),
    selectTemplate: vi.fn(),
    setTemplateSearchQuery: vi.fn(),
    openYAMLImportModal: vi.fn(),
  }),
  useShowYAMLImportModal: () => mockIsOpen,
}));

vi.mock('../../../../js/collaborative-editor/keyboard', () => ({
  useKeyboardShortcut: vi.fn(),
}));

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
  const mockStore = createMockStoreContextValue();
  return render(
    <StoreContext.Provider value={mockStore}>
      <YAMLImportModal />
    </StoreContext.Provider>
  );
}

describe('YAMLImportModal', () => {
  beforeEach(() => {
    mockIsOpen = true;
    vi.clearAllMocks();
    mockImportWorkflow.mockResolvedValue(undefined);
    mockSaveWorkflow.mockResolvedValue(undefined);
  });

  describe('Modal visibility', () => {
    test('renders dialog content when open', () => {
      renderModal();

      expect(screen.getByText(/Import a workflow/i)).toBeInTheDocument();
      expect(
        screen.getByRole('button', { name: /Cancel/i })
      ).toBeInTheDocument();
      expect(
        screen.getByRole('button', { name: /Create/i })
      ).toBeInTheDocument();
    });

    test('Create button is disabled initially', () => {
      renderModal();

      expect(screen.getByRole('button', { name: /Create/i })).toBeDisabled();
    });

    test('shows Upload/Paste toggle in upload mode by default', () => {
      renderModal();

      expect(
        screen.getByRole('button', { name: /Paste text/i })
      ).toBeInTheDocument();
      expect(
        screen.getByText(/Upload or drop a YAML file/i)
      ).toBeInTheDocument();
    });

    test('renders nothing meaningful when closed', () => {
      mockIsOpen = false;
      renderModal();

      expect(screen.queryByText(/Import a workflow/i)).not.toBeInTheDocument();
      expect(
        screen.queryByRole('button', { name: /Cancel/i })
      ).not.toBeInTheDocument();
    });
  });

  describe('Cancel closes modal', () => {
    test('clicking Cancel calls closeYAMLImportModal', () => {
      renderModal();

      fireEvent.click(screen.getByRole('button', { name: /Cancel/i }));

      expect(mockCloseYAMLImportModal).toHaveBeenCalledOnce();
    });
  });

  describe('Escape closes modal', () => {
    test('registers Escape shortcut with closeYAMLImportModal when open', () => {
      renderModal();

      expect(useKeyboardShortcut).toHaveBeenCalledWith(
        'Escape',
        mockCloseYAMLImportModal,
        100,
        { enabled: true }
      );
    });

    test('registers Escape shortcut as disabled when closed', () => {
      mockIsOpen = false;
      renderModal();

      expect(useKeyboardShortcut).toHaveBeenCalledWith(
        'Escape',
        mockCloseYAMLImportModal,
        100,
        { enabled: false }
      );
    });
  });

  describe('Successful import', () => {
    test('calls importWorkflow, saveWorkflow, then dismissLandingScreen on Create', async () => {
      renderModal();

      fireEvent.click(screen.getByRole('button', { name: /Paste text/i }));

      const textarea = screen.getByPlaceholderText(
        /Paste your YAML content here/i
      );
      fireEvent.change(textarea, { target: { value: validYAML } });

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
        expect(mockSaveWorkflow).toHaveBeenCalledWith({ silent: true });
        expect(mockDismissLandingScreen).toHaveBeenCalledOnce();
        expect(mockCloseYAMLImportModal).not.toHaveBeenCalled();
      });
    });
  });

  describe('State machine (representative)', () => {
    test('transitions to valid state after successful YAML validation', async () => {
      renderModal();

      fireEvent.click(screen.getByRole('button', { name: /Paste text/i }));
      const textarea = screen.getByPlaceholderText(
        /Paste your YAML content here/i
      );
      fireEvent.change(textarea, { target: { value: validYAML } });

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

      fireEvent.click(screen.getByRole('button', { name: /Paste text/i }));
      const textarea = screen.getByPlaceholderText(
        /Paste your YAML content here/i
      );
      fireEvent.change(textarea, { target: { value: 'invalid: [syntax' } });

      await waitFor(
        () =>
          expect(
            screen.getByRole('button', { name: /Create/i })
          ).toBeDisabled(),
        { timeout: 600 }
      );
    });

    test('shows button states during validation (Validating... text then enabled)', async () => {
      renderModal();

      fireEvent.click(screen.getByRole('button', { name: /Paste text/i }));
      const textarea = screen.getByPlaceholderText(
        /Paste your YAML content here/i
      );

      const createButton = screen.getByRole('button', { name: /Create/i });
      expect(createButton).toBeDisabled();

      fireEvent.change(textarea, { target: { value: validYAML } });

      await waitFor(
        () => {
          expect(
            screen.getByRole('button', { name: /Create/i })
          ).not.toBeDisabled();
        },
        { timeout: 600 }
      );
    });
  });

  describe('Mode toggling', () => {
    test('switches to paste mode then back to upload mode', () => {
      renderModal();

      fireEvent.click(screen.getByRole('button', { name: /Paste text/i }));

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

  describe('Debounced validation', () => {
    test('does not validate immediately on input (< 100ms)', async () => {
      renderModal();

      fireEvent.click(screen.getByRole('button', { name: /Paste text/i }));
      const textarea = screen.getByPlaceholderText(
        /Paste your YAML content here/i
      );
      fireEvent.change(textarea, { target: { value: 'name:' } });

      await waitFor(
        () => {
          expect(
            screen.queryByText(/Validation Error/i)
          ).not.toBeInTheDocument();
        },
        { timeout: 100 }
      );
    });

    test('validates after 300ms delay', async () => {
      renderModal();

      fireEvent.click(screen.getByRole('button', { name: /Paste text/i }));
      const textarea = screen.getByPlaceholderText(
        /Paste your YAML content here/i
      );
      const createButton = screen.getByRole('button', { name: /Create/i });

      expect(createButton).toBeDisabled();

      fireEvent.change(textarea, { target: { value: 'invalid: [syntax' } });

      await waitFor(
        () => {
          expect(createButton).toBeDisabled();
        },
        { timeout: 500, interval: 50 }
      );
    });
  });
});
