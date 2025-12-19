/**
 * TemplatePanel - Template-based workflow creation
 *
 * Architecture:
 * - Fetches templates via Phoenix Channel
 * - Shows template search and selection UI
 * - Previews templates on canvas
 * - Footer has Import button to switch to YAML import mode
 */

import { useCallback, useContext, useEffect, useMemo } from 'react';

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
import { useWorkflowActions } from '../../hooks/useWorkflow';
import { notifications } from '../../lib/notifications';
import type { Template } from '../../types/template';
import { Tooltip } from '../Tooltip';

import { TemplateCard } from './TemplateCard';
import { TemplateSearchInput } from './TemplateSearchInput';

interface TemplatePanelProps {
  onImportClick: () => void;
  onImport?: (workflowState: YAMLWorkflowState) => void;
}

export function TemplatePanel({ onImportClick, onImport }: TemplatePanelProps) {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error('TemplatePanel must be used within a StoreProvider');
  }
  const uiStore = context.uiStore;
  const aiStore = context.aiAssistantStore;
  const { provider } = useSession();
  const channel = provider?.channel;
  const { openAIAssistantPanel, collapseCreateWorkflowPanel } = useUICommands();
  const { saveWorkflow } = useWorkflowActions();

  const { templates, loading, error, searchQuery, selectedTemplate } =
    useTemplatePanel();

  // Clear template state on mount - always start fresh
  useEffect(() => {
    uiStore.selectTemplate(null);
    uiStore.setTemplateSearchQuery('');
  }, [uiStore]);

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
  }, [channel, uiStore]);

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
    [uiStore, onImport]
  );

  const handleSearchChange = (query: string) => {
    uiStore.setTemplateSearchQuery(query);
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
          onClick={onImportClick}
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
              onClick={() => void saveWorkflow()}
              disabled={!selectedTemplate}
              className="rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 disabled:bg-primary-300 disabled:hover:bg-primary-300 disabled:cursor-not-allowed"
            >
              Create
            </button>
          </span>
        </Tooltip>
      </div>
    </div>
  );
}
