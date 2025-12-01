/**
 * TemplatePanel - Template-based workflow creation
 *
 * Architecture:
 * - Fetches templates via Phoenix Channel
 * - Shows template search and selection UI
 * - Previews templates on canvas
 * - Footer has Import button to switch to YAML import mode
 */

import { useContext, useEffect, useMemo, useSyncExternalStore } from 'react';

import type { WorkflowState as YAMLWorkflowState } from '../../../yaml/types';
import {
  parseWorkflowYAML,
  convertWorkflowSpecToState,
} from '../../../yaml/util';
import { fetchTemplates } from '../../api/templates';
import { BASE_TEMPLATES } from '../../constants/baseTemplates';
import { StoreContext } from '../../contexts/StoreProvider';
import { useSession } from '../../hooks/useSession';
import { useUICommands } from '../../hooks/useUI';
import type { Template } from '../../types/template';

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
  const { provider } = useSession();
  const channel = provider?.channel;
  const { openAIAssistantPanel } = useUICommands();

  const templates = useSyncExternalStore(
    uiStore.subscribe,
    uiStore.withSelector(state => state.templatePanel.templates)
  );
  const loading = useSyncExternalStore(
    uiStore.subscribe,
    uiStore.withSelector(state => state.templatePanel.loading)
  );
  const error = useSyncExternalStore(
    uiStore.subscribe,
    uiStore.withSelector(state => state.templatePanel.error)
  );
  const searchQuery = useSyncExternalStore(
    uiStore.subscribe,
    uiStore.withSelector(state => state.templatePanel.searchQuery)
  );
  const selectedTemplate = useSyncExternalStore(
    uiStore.subscribe,
    uiStore.withSelector(state => state.templatePanel.selectedTemplate)
  );

  useEffect(() => {
    if (!channel) return;

    const loadTemplates = async () => {
      try {
        uiStore.setTemplatesLoading(true);
        const userTemplates = await fetchTemplates(channel);
        uiStore.setTemplates(userTemplates);

        // Select event-based template by default if no template is selected
        if (!selectedTemplate) {
          const eventBasedTemplate = BASE_TEMPLATES.find(
            t => t.id === 'base-webhook-template'
          );
          if (eventBasedTemplate) {
            handleSelectTemplate(eventBasedTemplate);
          }
        }
      } catch (err) {
        console.error('Failed to fetch templates:', err);
        uiStore.setTemplatesError('Failed to load templates');
      }
    };

    loadTemplates();

    return () => {
      uiStore.clearTemplatePanel();
    };
  }, [channel]);

  const filteredTemplates = useMemo(() => {
    if (!searchQuery.trim()) {
      return templates;
    }

    const query = searchQuery.toLowerCase();
    return templates.filter(template => {
      const matchName = template.name.toLowerCase().includes(query);
      const matchDesc = template.description?.toLowerCase().includes(query);
      const matchTags = template.tags.some(tag =>
        tag.toLowerCase().includes(query)
      );
      return matchName || matchDesc || matchTags;
    });
  }, [templates, searchQuery]);

  const allTemplates: Template[] = useMemo(
    () => [...BASE_TEMPLATES, ...filteredTemplates],
    [filteredTemplates]
  );

  const handleSelectTemplate = (template: Template) => {
    uiStore.selectTemplate(template);

    if (onImport) {
      try {
        const spec = parseWorkflowYAML(template.code);
        const state = convertWorkflowSpecToState(spec);
        onImport(state);
      } catch (err) {
        console.error('Failed to parse template:', err);
      }
    }
  };

  const handleCreateWorkflow = async () => {
    if (!selectedTemplate || !onImport || !onSave) return;

    try {
      const spec = parseWorkflowYAML(selectedTemplate.code);
      const state = convertWorkflowSpecToState(spec);
      onImport(state);
      await onSave();
    } catch (err) {
      console.error('Failed to create workflow from template:', err);
    }
  };

  const handleSearchChange = (query: string) => {
    uiStore.setTemplateSearchQuery(query);
  };

  return (
    <div className="w-full h-full flex flex-col bg-white border-r border-gray-200">
      <div className="shrink-0 px-4 py-4 border-b border-gray-200">
        <TemplateSearchInput
          value={searchQuery}
          onChange={handleSearchChange}
          placeholder="Search templates by name, description, or tags..."
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
            <div className="text-red-600">{error}</div>
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

            {filteredTemplates.length === 0 && searchQuery && (
              <div className="col-span-full flex items-center justify-center h-64">
                <div className="text-center text-gray-500">
                  <p className="text-base mb-3">
                    No user templates found matching your search
                  </p>
                  <button
                    type="button"
                    onClick={openAIAssistantPanel}
                    className="text-sm text-primary-600 hover:text-primary-700 font-medium underline"
                  >
                    Build your own template using the AI Assistant
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
        <button
          type="button"
          onClick={handleCreateWorkflow}
          disabled={!selectedTemplate || !onSave}
          className="rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 disabled:bg-gray-300 disabled:cursor-not-allowed"
        >
          Create
        </button>
      </div>
    </div>
  );
}
