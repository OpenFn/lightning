/**
 * TemplatePanel - Template-based workflow creation
 *
 * Architecture:
 * - Fetches templates via Phoenix Channel
 * - Shows template search and selection UI
 * - Previews templates on canvas
 * - Footer has Import button to switch to YAML import mode
 */

import { useCallback, useContext, useEffect, useMemo, useRef } from 'react';

import { useURLState } from '../../../react/lib/use-url-state';
import type { WorkflowState as YAMLWorkflowState } from '../../../yaml/types';
import {
  parseWorkflowYAML,
  convertWorkflowSpecToState,
} from '../../../yaml/util';
import { fetchTemplates } from '../../api/templates';
import { BASE_TEMPLATES } from '../../constants/baseTemplates';
import { StoreContext } from '../../contexts/StoreProvider';
import { useSession } from '../../hooks/useSession';
import { useTemplatePanel, useUICommands } from '../../hooks/useUI';
import { notifications } from '../../lib/notifications';
import type { Template } from '../../types/template';
import { Tooltip } from '../Tooltip';

import { TemplateCard } from './TemplateCard';
import { TemplateSearchInput } from './TemplateSearchInput';

interface TemplatePanelProps {
  onImportClick: () => void;
  onImport?: (workflowState: YAMLWorkflowState) => void;
  onSave?: () => Promise<unknown>;
}

export function TemplatePanel({
  onImportClick,
  onImport,
  onSave,
}: TemplatePanelProps) {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error('TemplatePanel must be used within a StoreProvider');
  }
  const uiStore = context.uiStore;
  const aiStore = context.aiAssistantStore;
  const { provider } = useSession();
  const channel = provider?.channel;
  const { openAIAssistantPanel, collapseCreateWorkflowPanel } = useUICommands();
  const { params, updateSearchParams } = useURLState();

  const { templates, loading, error, searchQuery, selectedTemplate } =
    useTemplatePanel();

  /**
   * previousTemplateRef tracks the selected template before user starts searching.
   * When search is cleared (query becomes empty), we restore this selection.
   * This provides a better UX than losing the selection during search exploration.
   *
   * Why a ref instead of store state:
   * - This is local to the search behavior within this component
   * - Moving to store would add complexity without benefit (clearing on unmount, etc.)
   * - The ref pattern keeps the restore logic self-contained
   */
  const previousTemplateRef = useRef<Template | null>(null);

  useEffect(() => {
    if (!channel) return;

    const loadTemplates = async () => {
      try {
        uiStore.setTemplatesLoading(true);
        const userTemplates = await fetchTemplates(channel);
        uiStore.setTemplates(userTemplates);
      } catch (err) {
        console.error('Failed to fetch templates:', err);
        uiStore.setTemplatesError('Failed to load templates');
      }
    };

    void loadTemplates();
    // Note: No cleanup - we preserve template selection when switching between panels
  }, [channel, uiStore]);

  // Restore search query from URL on initial mount only
  const hasRestoredSearchRef = useRef(false);
  useEffect(() => {
    if (hasRestoredSearchRef.current) return;

    const urlSearchQuery = params['search'];
    if (urlSearchQuery && urlSearchQuery !== searchQuery) {
      uiStore.setTemplateSearchQuery(urlSearchQuery);
    }
    hasRestoredSearchRef.current = true;
  }, [params, searchQuery, uiStore]);

  const allTemplates: Template[] = useMemo(() => {
    const combined = [...BASE_TEMPLATES, ...templates];

    if (!searchQuery.trim()) {
      return combined;
    }

    const query = searchQuery.toLowerCase();
    return combined.filter(template => {
      const matchName = template.name.toLowerCase().includes(query);
      const matchDesc = template.description?.toLowerCase().includes(query);
      const matchTags = template.tags.some(tag =>
        tag.toLowerCase().includes(query)
      );
      return matchName || matchDesc || matchTags;
    });
  }, [templates, searchQuery]);

  const handleSelectTemplate = useCallback(
    (template: Template) => {
      uiStore.selectTemplate(template);
      updateSearchParams({ template: template.id });

      if (onImport) {
        try {
          const spec = parseWorkflowYAML(template.code);
          const state = convertWorkflowSpecToState(spec);
          onImport(state);
        } catch (err) {
          console.error('Failed to parse template:', err);
          notifications.alert({
            title: 'Failed to load template',
            description:
              'The template YAML could not be parsed. Please try another template.',
          });
        }
      }
    },
    [uiStore, updateSearchParams, onImport]
  );

  // Restore template selection from URL and render on canvas
  const hasRenderedTemplateRef = useRef(false);
  useEffect(() => {
    const templateId = params['template'];

    // No template selected - clear canvas on mount
    if (!templateId && !hasRenderedTemplateRef.current) {
      hasRenderedTemplateRef.current = true;
      if (onImport) {
        onImport({
          id: '',
          name: '',
          jobs: [],
          triggers: [],
          edges: [],
          positions: null,
        });
      }
      return;
    }

    if (!templateId || templates.length === 0) return;

    // Find template in combined list
    const allTemplatesList = [...BASE_TEMPLATES, ...templates];
    const template = allTemplatesList.find(t => t.id === templateId);

    if (template) {
      // If already selected in store but not rendered yet, just render on canvas
      if (
        selectedTemplate?.id === templateId &&
        !hasRenderedTemplateRef.current
      ) {
        hasRenderedTemplateRef.current = true;
        if (onImport) {
          try {
            const spec = parseWorkflowYAML(template.code);
            const state = convertWorkflowSpecToState(spec);
            onImport(state);
          } catch (err) {
            console.error('Failed to parse template:', err);
            notifications.alert({
              title: 'Failed to load template',
              description:
                'The template YAML could not be parsed. Please try another template.',
            });
          }
        }
      } else if (selectedTemplate?.id !== templateId) {
        // Different template - select and render
        hasRenderedTemplateRef.current = true;
        handleSelectTemplate(template);
      }
    }
  }, [params, templates, selectedTemplate, handleSelectTemplate, onImport]);

  const handleCreateWorkflow = async () => {
    if (!selectedTemplate || !onImport || !onSave) return;

    try {
      const spec = parseWorkflowYAML(selectedTemplate.code);
      const state = convertWorkflowSpecToState(spec);
      onImport(state);
      await onSave();

      // After successful save, collapse panel and clear template params
      collapseCreateWorkflowPanel();
      uiStore.selectTemplate(null);
      uiStore.setTemplateSearchQuery('');
      updateSearchParams({ template: null, search: null });
    } catch (err) {
      console.error('Failed to create workflow from template:', err);
      notifications.alert({
        title: 'Failed to create workflow',
        description:
          'The template could not be processed. Please try again or select another template.',
      });
    }
  };

  const handleSearchChange = (query: string) => {
    const previousQuery = searchQuery;
    uiStore.setTemplateSearchQuery(query);
    updateSearchParams({ search: query || null });

    // Starting a search - save current selection and clear canvas
    if (query && !previousQuery && selectedTemplate && onImport) {
      previousTemplateRef.current = selectedTemplate;
      uiStore.selectTemplate(null);
      updateSearchParams({ template: null, search: query });
      // Import empty workflow to clear canvas
      onImport({
        id: '',
        name: '',
        jobs: [],
        triggers: [],
        edges: [],
        positions: null,
      });
    }
    // Clearing search - restore previous selection
    else if (!query && previousQuery && previousTemplateRef.current) {
      const templateToRestore = previousTemplateRef.current;
      previousTemplateRef.current = null;
      handleSelectTemplate(templateToRestore);
    }
  };

  const handleBuildWithAI = useCallback(() => {
    // Only trigger if there are no matching templates and there's a search query
    if (allTemplates.length === 0 && searchQuery) {
      // Clear any existing AI session and disconnect
      aiStore.disconnect();
      aiStore.clearSession();

      // Close the template panel before opening AI Assistant
      collapseCreateWorkflowPanel();

      openAIAssistantPanel(searchQuery);
    }
  }, [
    allTemplates.length,
    searchQuery,
    aiStore,
    collapseCreateWorkflowPanel,
    openAIAssistantPanel,
  ]);

  return (
    <div className="w-full h-full flex flex-col bg-white border-r border-gray-200">
      <div className="shrink-0 px-4 py-4 border-b border-gray-200">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-lg font-semibold text-gray-900">
            Browse templates
          </h2>
          <button
            type="button"
            onClick={collapseCreateWorkflowPanel}
            className="rounded hover:bg-gray-100 transition-colors"
            aria-label="Collapse panel"
          >
            <span className="hero-chevron-left h-5 w-5 text-gray-600" />
          </button>
        </div>
        <TemplateSearchInput
          value={searchQuery}
          onChange={handleSearchChange}
          onEnter={handleBuildWithAI}
          placeholder="Search templates by name, description, or tags..."
          focusOnMount
        />
      </div>

      <div className="flex-1 overflow-y-auto px-4 py-4">
        {loading && (
          <div className="flex items-center justify-center h-64">
            <div className="text-gray-500">Loading templates...</div>
          </div>
        )}

        {error && (
          <div className="flex items-center justify-center h-64">
            <div className="text-center max-w-md">
              <div className="inline-flex items-center justify-center w-14 h-14 rounded-full bg-red-100 mb-5">
                <span className="hero-exclamation-triangle h-7 w-7 text-red-600" />
              </div>
              <h3 className="text-base font-medium text-gray-900 mb-2">
                Failed to load templates
              </h3>
              <p className="text-sm text-gray-600 mb-4">{error}</p>
              <button
                type="button"
                onClick={() => {
                  if (!channel) return;
                  uiStore.setTemplatesError(null);
                  void (async () => {
                    try {
                      uiStore.setTemplatesLoading(true);
                      const userTemplates = await fetchTemplates(channel);
                      uiStore.setTemplates(userTemplates);
                    } catch (err) {
                      console.error('Failed to fetch templates:', err);
                      uiStore.setTemplatesError('Failed to load templates');
                    }
                  })();
                }}
                className="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
              >
                <span className="hero-arrow-path h-4 w-4" />
                Try again
              </button>
            </div>
          </div>
        )}

        {!loading && !error && (
          <div className="grid grid-cols-1 xl:grid-cols-2 gap-2">
            {allTemplates.map(template => (
              <TemplateCard
                key={template.id}
                template={template}
                isSelected={selectedTemplate?.id === template.id}
                onClick={handleSelectTemplate}
              />
            ))}

            {allTemplates.length === 0 && searchQuery && (
              <div className="col-span-full flex items-center justify-center h-64">
                <div className="text-center max-w-md">
                  <div className="inline-flex items-center justify-center w-14 h-14 rounded-full bg-gray-100 mb-5">
                    <span className="hero-magnifying-glass h-7 w-7 text-gray-400" />
                  </div>
                  <h3 className="text-base font-medium text-gray-900 mb-2">
                    No matching templates
                  </h3>
                  <p className="text-sm text-gray-600 mb-6">
                    We couldn't find any templates for "
                    <span className="font-medium text-gray-900">
                      {searchQuery}
                    </span>
                    "
                  </p>
                  <button
                    type="button"
                    onClick={handleBuildWithAI}
                    className="group relative inline-flex items-center gap-2 rounded-lg bg-gradient-to-br from-primary-600 via-primary-500 to-primary-600 px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition-all duration-200 hover:shadow-md hover:scale-[1.02] active:scale-[0.98]"
                  >
                    <span className="hero-sparkles h-4 w-4 group-hover:rotate-12 transition-transform duration-200" />
                    Build your workflow using AI
                    <span className="hero-arrow-right h-4 w-4 group-hover:translate-x-0.5 transition-transform duration-200" />
                  </button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      <div className="shrink-0 border-t border-gray-200 px-4 py-4 flex justify-end gap-2">
        <button
          type="button"
          onClick={() => {
            // Clear URL params but keep template selection in store for when user returns
            updateSearchParams({ template: null, search: null });
            onImportClick();
          }}
          className="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 inline-flex items-center gap-x-2"
        >
          <span className="hero-document-arrow-up size-5" />
          Import
        </button>
        <Tooltip
          content={
            !selectedTemplate ? 'Select a template to create workflow' : null
          }
          side="bottom"
        >
          <span className="inline-block">
            <button
              type="button"
              onClick={() => void handleCreateWorkflow()}
              disabled={!selectedTemplate || !onSave}
              className="rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:bg-primary-600"
            >
              Create
            </button>
          </span>
        </Tooltip>
      </div>
    </div>
  );
}
