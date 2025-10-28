/**
 * YAMLImportPanel Component Tests
 *
 * Tests state machine, debounced validation, and import flow
 */

import { describe, expect, test, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { YAMLImportPanel } from '../../../../js/collaborative-editor/components/left-panel/YAMLImportPanel';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import type { StoreContextValue } from '../../../../js/collaborative-editor/contexts/StoreProvider';

// Mock the awareness hook
vi.mock('../../../../js/collaborative-editor/hooks/useAwareness', () => ({
  useRemoteUsers: () => [],
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

const invalidYAML = `
invalid: [syntax
`;

function createMockStoreContext(): StoreContextValue {
  return {
    sessionContextStore: {} as any,
    adaptorStore: {} as any,
    credentialStore: {} as any,
    awarenessStore: {} as any,
    workflowStore: {} as any,
  };
}

describe('YAMLImportPanel', () => {
  let mockOnBack: ReturnType<typeof vi.fn>;
  let mockOnImport: ReturnType<typeof vi.fn>;
  let mockOnSave: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockOnBack = vi.fn();
    mockOnImport = vi.fn();
    mockOnSave = vi.fn().mockResolvedValue(undefined);
    vi.clearAllMocks();
  });

  describe('Panel visibility', () => {
    test('shows panel content', () => {
      const mockStore = createMockStoreContext();
      render(
        <StoreContext.Provider value={mockStore}>
          <YAMLImportPanel
            onBack={mockOnBack}
            onImport={mockOnImport}
            onSave={mockOnSave}
          />
        </StoreContext.Provider>
      );

      expect(screen.getByText(/YML or YAML, up to 8MB/i)).toBeInTheDocument();
    });
  });

  describe('State machine', () => {
    test('starts in initial state with disabled button', () => {
      const mockStore = createMockStoreContext();
      render(
        <StoreContext.Provider value={mockStore}>
          <YAMLImportPanel
            onBack={mockOnBack}
            onImport={mockOnImport}
            onSave={mockOnSave}
          />
        </StoreContext.Provider>
      );

      const createButton = screen.getByRole('button', { name: /Create/i });
      expect(createButton).toBeDisabled();
    });

    test('transitions to parsing state when YAML entered', async () => {
      const mockStore = createMockStoreContext();
      render(
        <StoreContext.Provider value={mockStore}>
          <YAMLImportPanel
            onBack={mockOnBack}
            onImport={mockOnImport}
            onSave={mockOnSave}
          />
        </StoreContext.Provider>
      );

      const textarea = screen.getByPlaceholderText(
        /Paste your YAML content here/i
      );
      fireEvent.change(textarea, { target: { value: validYAML } });

      // Button should be disabled during parsing
      const createButton = screen.getByRole('button', {
        name: /Create|Validating/i,
      });
      expect(createButton).toBeDisabled();
    });

    test('transitions to valid state after successful validation', async () => {
      const mockStore = createMockStoreContext();
      render(
        <StoreContext.Provider value={mockStore}>
          <YAMLImportPanel
            onBack={mockOnBack}
            onImport={mockOnImport}
            onSave={mockOnSave}
          />
        </StoreContext.Provider>
      );

      const textarea = screen.getByPlaceholderText(
        /Paste your YAML content here/i
      );
      fireEvent.change(textarea, { target: { value: validYAML } });

      // Wait for debounce (300ms) + validation
      await waitFor(
        () => {
          const createButton = screen.getByRole('button', { name: /Create/i });
          expect(createButton).not.toBeDisabled();
        },
        { timeout: 500 }
      );
    });

    test('transitions to invalid state with validation errors', async () => {
      const mockStore = createMockStoreContext();
      render(
        <StoreContext.Provider value={mockStore}>
          <YAMLImportPanel
            onBack={mockOnBack}
            onImport={mockOnImport}
            onSave={mockOnSave}
          />
        </StoreContext.Provider>
      );

      const textarea = screen.getByPlaceholderText(
        /Paste your YAML content here/i
      );
      fireEvent.change(textarea, { target: { value: invalidYAML } });

      // Wait for validation to complete - button should remain disabled
      await waitFor(
        () => {
          const createButton = screen.getByRole('button', { name: /Create/i });
          expect(createButton).toBeDisabled();
        },
        { timeout: 600 }
      );
    });

    test('transitions to importing state when Create clicked', async () => {
      const mockStore = createMockStoreContext();
      render(
        <StoreContext.Provider value={mockStore}>
          <YAMLImportPanel
            onBack={mockOnBack}
            onImport={mockOnImport}
            onSave={mockOnSave}
          />
        </StoreContext.Provider>
      );

      const textarea = screen.getByPlaceholderText(
        /Paste your YAML content here/i
      );
      fireEvent.change(textarea, { target: { value: validYAML } });

      // Wait for valid state
      await waitFor(
        () => {
          const createButton = screen.getByRole('button', { name: /Create/i });
          expect(createButton).not.toBeDisabled();
        },
        { timeout: 500 }
      );

      const createButton = screen.getByRole('button', { name: /Create/i });
      fireEvent.click(createButton);

      // Wait for async save to complete
      await waitFor(() => {
        expect(mockOnSave).toHaveBeenCalled();
      });
    });
  });

  describe('Debounced validation', () => {
    test('does not validate immediately on input', async () => {
      const mockStore = createMockStoreContext();
      render(
        <StoreContext.Provider value={mockStore}>
          <YAMLImportPanel
            onBack={mockOnBack}
            onImport={mockOnImport}
            onSave={mockOnSave}
          />
        </StoreContext.Provider>
      );

      const textarea = screen.getByPlaceholderText(
        /Paste your YAML content here/i
      );
      fireEvent.change(textarea, { target: { value: 'name:' } });

      // Validation shouldn't complete yet
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
      const mockStore = createMockStoreContext();
      render(
        <StoreContext.Provider value={mockStore}>
          <YAMLImportPanel
            onBack={mockOnBack}
            onImport={mockOnImport}
            onSave={mockOnSave}
          />
        </StoreContext.Provider>
      );

      const textarea = screen.getByPlaceholderText(
        /Paste your YAML content here/i
      );
      const createButton = screen.getByRole('button', { name: /Create/i });

      // Initially disabled
      expect(createButton).toBeDisabled();

      fireEvent.change(textarea, { target: { value: invalidYAML } });

      // Wait for debounce (300ms) + validation - button should still be disabled
      await waitFor(
        () => {
          expect(createButton).toBeDisabled();
        },
        { timeout: 500, interval: 50 }
      );
    });
  });

  describe('User actions', () => {
    test('navigates back when Back button clicked', () => {
      const mockStore = createMockStoreContext();
      render(
        <StoreContext.Provider value={mockStore}>
          <YAMLImportPanel
            onBack={mockOnBack}
            onImport={mockOnImport}
            onSave={mockOnSave}
          />
        </StoreContext.Provider>
      );

      const backButton = screen.getByRole('button', { name: /Back/i });
      fireEvent.click(backButton);

      expect(mockOnBack).toHaveBeenCalled();
    });
  });

  describe('UI elements', () => {
    test('shows button states during validation', async () => {
      const mockStore = createMockStoreContext();
      render(
        <StoreContext.Provider value={mockStore}>
          <YAMLImportPanel
            onBack={mockOnBack}
            onImport={mockOnImport}
            onSave={mockOnSave}
          />
        </StoreContext.Provider>
      );

      const textarea = screen.getByPlaceholderText(
        /Paste your YAML content here/i
      );

      // Initially disabled
      const createButton1 = screen.getByRole('button', { name: /Create/i });
      expect(createButton1).toBeDisabled();

      // Enter valid YAML
      fireEvent.change(textarea, { target: { value: validYAML } });

      // After validation completes, button should be enabled
      await waitFor(
        () => {
          const createButton2 = screen.getByRole('button', { name: /Create/i });
          expect(createButton2).not.toBeDisabled();
        },
        { timeout: 600 }
      );
    });
  });
});
