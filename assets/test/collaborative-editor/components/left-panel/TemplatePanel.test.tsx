/**
 * TemplatePanel Component Tests
 *
 * Phase 5 of #4718: the template picker reads `WorkflowTemplate.code` (a
 * stored YAML string) and parses it via the format-aware
 * `parseWorkflowTemplate`. Existing rows in the DB are v1; new rows
 * published from the canvas (Phase 4 onward) are v2. This test fixture
 * proves both shapes load identically through the picker.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { describe, expect, test, vi, beforeEach } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';

import { TemplatePanel } from '../../../../js/collaborative-editor/components/left-panel/TemplatePanel';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import type { Template } from '../../../../js/collaborative-editor/types/template';
import { createMockStoreContextValue } from '../../__helpers__';

// Hoisted mock state — vi.mock factories must reference it via vi.hoisted.
const mockState = vi.hoisted(() => ({
  templates: [] as Template[],
  searchQuery: '',
  selectedTemplate: null as Template | null,
  loading: false,
  error: null as string | null,
}));

vi.mock('../../../../js/collaborative-editor/hooks/useUI', () => ({
  useTemplatePanel: () => ({
    templates: mockState.templates,
    loading: mockState.loading,
    error: mockState.error,
    searchQuery: mockState.searchQuery,
    selectedTemplate: mockState.selectedTemplate,
  }),
  useUICommands: () => ({
    openAIAssistantPanel: vi.fn(),
    collapseCreateWorkflowPanel: vi.fn(),
  }),
}));

vi.mock('../../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: () => ({ provider: null }),
}));

vi.mock('../../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowActions: () => ({ saveWorkflow: vi.fn() }),
}));

vi.mock('../../../../js/collaborative-editor/api/templates', () => ({
  fetchTemplates: vi.fn().mockResolvedValue([]),
}));

vi.mock('../../../../js/collaborative-editor/constants/baseTemplates', () => ({
  BASE_TEMPLATES: [],
}));

const FIXTURES_ROOT = resolve(
  __dirname,
  '../../../../../test/fixtures/portability'
);

// Kitchen-sink fixture: comprehensive workflow exercising every supported
// feature in both formats. New features must be added here so regressions
// in the template loader surface.
const readKitchenSink = (format: 'v1' | 'v2'): string =>
  readFileSync(`${FIXTURES_ROOT}/${format}/canonical_workflow.yaml`, 'utf-8');

const makeTemplate = (id: string, name: string, code: string): Template => ({
  id,
  name,
  description: `Template fixture ${id}`,
  code,
  positions: null,
  tags: [],
  workflow_id: null,
});

describe('TemplatePanel — format dispatch (v1 + v2)', () => {
  let mockOnImport: ReturnType<typeof vi.fn>;
  let mockOnImportClick: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockOnImport = vi.fn();
    mockOnImportClick = vi.fn();
    mockState.templates = [];
    mockState.searchQuery = '';
    mockState.selectedTemplate = null;
    mockState.loading = false;
    mockState.error = null;
    vi.clearAllMocks();
  });

  test('loads a v1-formatted canonical workflow template when picked', async () => {
    const template = makeTemplate(
      'v1-canonical',
      'v1 canonical',
      readKitchenSink('v1')
    );
    mockState.templates = [template];

    const mockStore = createMockStoreContextValue();
    render(
      <StoreContext.Provider value={mockStore}>
        <TemplatePanel
          onImportClick={mockOnImportClick}
          onImport={mockOnImport}
        />
      </StoreContext.Provider>
    );

    const card = await screen.findByText('v1 canonical');
    fireEvent.click(card);

    await waitFor(() => {
      expect(mockOnImport).toHaveBeenCalled();
    });

    const lastCall =
      mockOnImport.mock.calls[mockOnImport.mock.calls.length - 1];
    const state = lastCall[0];
    expect(state).toBeDefined();
    expect(Array.isArray(state.jobs)).toBe(true);
    expect(state.jobs.length).toBeGreaterThan(0);
    expect(Array.isArray(state.triggers)).toBe(true);
    expect(state.triggers.length).toBeGreaterThan(0);
  });

  test('loads a v2-formatted canonical workflow template when picked', async () => {
    const template = makeTemplate(
      'v2-canonical',
      'v2 canonical',
      readKitchenSink('v2')
    );
    mockState.templates = [template];

    const mockStore = createMockStoreContextValue();
    render(
      <StoreContext.Provider value={mockStore}>
        <TemplatePanel
          onImportClick={mockOnImportClick}
          onImport={mockOnImport}
        />
      </StoreContext.Provider>
    );

    const card = await screen.findByText('v2 canonical');
    fireEvent.click(card);

    await waitFor(() => {
      expect(mockOnImport).toHaveBeenCalled();
    });

    const lastCall =
      mockOnImport.mock.calls[mockOnImport.mock.calls.length - 1];
    const state = lastCall[0];
    expect(state).toBeDefined();
    expect(Array.isArray(state.jobs)).toBe(true);
    expect(state.jobs.length).toBeGreaterThan(0);
    expect(Array.isArray(state.triggers)).toBe(true);
    expect(state.triggers.length).toBeGreaterThan(0);
  });

  test('produces structurally equivalent state for v1 and v2 canonical workflows', async () => {
    const v1Template = makeTemplate(
      'v1-canonical',
      'v1 canonical',
      readKitchenSink('v1')
    );
    const v2Template = makeTemplate(
      'v2-canonical',
      'v2 canonical',
      readKitchenSink('v2')
    );
    mockState.templates = [v1Template, v2Template];

    const mockStore = createMockStoreContextValue();
    render(
      <StoreContext.Provider value={mockStore}>
        <TemplatePanel
          onImportClick={mockOnImportClick}
          onImport={mockOnImport}
        />
      </StoreContext.Provider>
    );

    fireEvent.click(await screen.findByText('v1 canonical'));
    await waitFor(() => expect(mockOnImport).toHaveBeenCalledTimes(1));
    const v1State = mockOnImport.mock.calls[0][0];

    fireEvent.click(await screen.findByText('v2 canonical'));
    await waitFor(() => expect(mockOnImport).toHaveBeenCalledTimes(2));
    const v2State = mockOnImport.mock.calls[1][0];

    expect(v1State.jobs.length).toBe(v2State.jobs.length);
    expect(v1State.triggers.length).toBe(v2State.triggers.length);
    expect(v1State.edges.length).toBe(v2State.edges.length);
  });
});
