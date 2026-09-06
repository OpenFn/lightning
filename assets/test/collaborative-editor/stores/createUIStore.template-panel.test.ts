/**
 * createUIStore — template panel slice tests
 *
 * Tests the templatePanel initial state and setTemplates/setTemplatesLoading/
 * setTemplateSearchQuery commands in isolation against the real createUIStore
 * implementation.
 */

import { describe, expect, test } from 'vitest';

import { BASE_TEMPLATES } from '../../../js/collaborative-editor/constants/baseTemplates';
import { createUIStore } from '../../../js/collaborative-editor/stores/createUIStore';
import type { Template } from '../../../js/collaborative-editor/types/template';

// =============================================================================
// INITIAL STATE
// =============================================================================

describe('createUIStore — template panel initial state', () => {
  test('templatePanel starts seeded with the base templates, not loading, with an empty search query', () => {
    const store = createUIStore();
    expect(store.getSnapshot().templatePanel).toEqual({
      templates: BASE_TEMPLATES,
      loading: false,
      searchQuery: '',
    });
  });
});

// =============================================================================
// setTemplates COMMAND
// =============================================================================

describe('createUIStore — setTemplates', () => {
  test('replaces templatePanel.templates', () => {
    const store = createUIStore();
    const templates: Template[] = [
      {
        id: 'user-template-1',
        name: 'Custom template',
        description: 'A user-authored template',
        code: 'name: "Custom template"',
        positions: null,
        tags: [],
        workflow_id: 'workflow-1',
      },
    ];

    store.setTemplates(templates);

    expect(store.getSnapshot().templatePanel.templates).toEqual(templates);
  });
});

// =============================================================================
// setTemplatesLoading COMMAND
// =============================================================================

describe('createUIStore — setTemplatesLoading', () => {
  test('toggles templatePanel.loading', () => {
    const store = createUIStore();

    store.setTemplatesLoading(true);
    expect(store.getSnapshot().templatePanel.loading).toBe(true);

    store.setTemplatesLoading(false);
    expect(store.getSnapshot().templatePanel.loading).toBe(false);
  });
});

// =============================================================================
// setTemplateSearchQuery COMMAND
// =============================================================================

describe('createUIStore — setTemplateSearchQuery', () => {
  test('updates templatePanel.searchQuery', () => {
    const store = createUIStore();

    store.setTemplateSearchQuery('webhook');

    expect(store.getSnapshot().templatePanel.searchQuery).toBe('webhook');
  });
});
