/**
 * YAMLImportPanel Component Tests
 *
 * Tests state machine, debounced validation, and import flow
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { describe, expect, test, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { YAMLImportPanel } from '../../../../js/collaborative-editor/components/left-panel/YAMLImportPanel';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { createMockStoreContextValue } from '../../__helpers__';

const FIXTURES_ROOT = resolve(
  __dirname,
  '../../../../../test/fixtures/portability'
);

const readScenario = (format: 'v1' | 'v2', name: string): string =>
  readFileSync(`${FIXTURES_ROOT}/${format}/scenarios/${name}.yaml`, 'utf-8');

// Mock the awareness hook
vi.mock('../../../../js/collaborative-editor/hooks/useAwareness', () => ({
  useAwareness: () => [],
}));

// Mock UI hooks
vi.mock('../../../../js/collaborative-editor/hooks/useUI', () => ({
  useUICommands: () => ({
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
  }),
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
      const mockStore = createMockStoreContextValue();
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
      const mockStore = createMockStoreContextValue();
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
      const mockStore = createMockStoreContextValue();
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
        /Paste your workflow YAML here/i
      );
      fireEvent.change(textarea, { target: { value: validYAML } });

      // Button should be disabled during parsing
      const createButton = screen.getByRole('button', {
        name: /Create|Validating/i,
      });
      expect(createButton).toBeDisabled();
    });

    test('transitions to valid state after successful validation', async () => {
      const mockStore = createMockStoreContextValue();
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
        /Paste your workflow YAML here/i
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
      const mockStore = createMockStoreContextValue();
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
        /Paste your workflow YAML here/i
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
      const mockStore = createMockStoreContextValue();
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
        /Paste your workflow YAML here/i
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
      const mockStore = createMockStoreContextValue();
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
        /Paste your workflow YAML here/i
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
      const mockStore = createMockStoreContextValue();
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
        /Paste your workflow YAML here/i
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
      const mockStore = createMockStoreContextValue();
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
      const mockStore = createMockStoreContextValue();
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
        /Paste your workflow YAML here/i
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

  // Phase 5 of #4718: import accepts both v1 (legacy Lightning) and v2
  // (CLI-aligned portability spec) YAML transparently. The panel itself is
  // format-agnostic; it routes through `parseWorkflowYAML` which auto-detects.
  describe('Format dispatch (v1 + v2)', () => {
    // Each scenario lists the workflow name and the exact job/trigger names
    // declared in BOTH the v1 and v2 fixtures (paired in
    // test/fixtures/portability/{v1,v2}/scenarios/<name>.yaml). Asserting on
    // the last populated onImport call's content catches a regression that
    // silently truncates jobs/triggers — the previous `length > 0` check
    // would have passed even if only the first job came through.
    const SCENARIOS = [
      {
        name: 'simple-webhook',
        workflow: 'simple webhook',
        jobs: ['greet'],
        triggers: ['webhook'],
      },
      {
        name: 'cron-with-cursor',
        workflow: 'cron with cursor',
        jobs: ['cursor step'],
        triggers: ['cron'],
      },
      {
        name: 'js-expression-edge',
        workflow: 'js expression edge',
        jobs: ['source step', 'target step'],
        triggers: ['webhook'],
      },
      {
        name: 'multi-trigger',
        workflow: 'multi trigger',
        jobs: ['shared step'],
        triggers: ['webhook', 'cron'],
      },
      {
        name: 'kafka-trigger',
        workflow: 'kafka trigger',
        jobs: ['consume'],
        triggers: ['kafka'],
      },
      {
        name: 'branching-jobs',
        workflow: 'branching jobs',
        jobs: ['fan out', 'branch a', 'branch b'],
        triggers: ['webhook'],
      },
    ] as const;

    const lastPopulatedState = (
      mockFn: ReturnType<typeof vi.fn>
    ): { jobs: { name: string }[]; triggers: { type: string }[] } | null => {
      const populated = mockFn.mock.calls.filter(
        ([state]) => state && state.jobs && state.jobs.length > 0
      );
      const last = populated[populated.length - 1];
      return last ? last[0] : null;
    };

    const renderAndImport = async (yaml: string) => {
      const mockStore = createMockStoreContextValue();
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
        /Paste your workflow YAML here/i
      );
      fireEvent.change(textarea, { target: { value: yaml } });

      await waitFor(
        () => {
          const createButton = screen.getByRole('button', { name: /Create/i });
          expect(createButton).not.toBeDisabled();
        },
        { timeout: 600 }
      );
    };

    test.each(SCENARIOS)(
      'accepts v1 fixture for $name and previews via onImport',
      async ({ name, jobs, triggers }) => {
        await renderAndImport(readScenario('v1', name));

        const state = lastPopulatedState(mockOnImport);
        expect(state).not.toBeNull();
        expect(state!.jobs.map(j => j.name).sort()).toEqual([...jobs].sort());
        expect(state!.triggers.map(t => t.type).sort()).toEqual(
          [...triggers].sort()
        );
      }
    );

    test.each(SCENARIOS)(
      'accepts v2 fixture for $name and previews via onImport',
      async ({ name, jobs, triggers }) => {
        await renderAndImport(readScenario('v2', name));

        const state = lastPopulatedState(mockOnImport);
        expect(state).not.toBeNull();
        expect(state!.jobs.map(j => j.name).sort()).toEqual([...jobs].sort());
        expect(state!.triggers.map(t => t.type).sort()).toEqual(
          [...triggers].sort()
        );
      }
    );
  });
});
