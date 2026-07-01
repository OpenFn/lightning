import { useEffect, useState } from 'react';

import { parseWorkflowYAML, convertWorkflowSpecToState } from '../../yaml/util';
import { fetchTemplates } from '../api/templates';
import { BASE_TEMPLATES } from '../constants/baseTemplates';
import { useSession } from '../hooks/useSession';
import { useShowTemplateBrowserModal, useUICommands } from '../hooks/useUI';
import { useWorkflowActions } from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';
import { notifications } from '../lib/notifications';
import type { Template } from '../types/template';

import { TemplateBrowserModal } from './TemplateBrowserModal';

export function TemplateBrowserModalWrapper() {
  const isOpen = useShowTemplateBrowserModal();
  const { closeTemplateBrowserModal, dismissLandingScreen } = useUICommands();
  const { provider } = useSession();
  const channel = provider?.channel;
  const { importWorkflow, saveWorkflow } = useWorkflowActions();

  const [templates, setTemplates] = useState<Template[]>(BASE_TEMPLATES);
  const [loading, setLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');

  useKeyboardShortcut('Escape', closeTemplateBrowserModal, 100, {
    enabled: isOpen,
  });

  // Lazy fetch — only when modal opens, not on every /new load
  useEffect(() => {
    if (!isOpen || !channel) return;

    setSearchQuery('');

    const load = async () => {
      setLoading(true);
      try {
        const userTemplates = await fetchTemplates(channel);
        setTemplates([...BASE_TEMPLATES, ...userTemplates]);
      } catch {
        notifications.alert({
          title: 'Failed to load templates',
          description: 'Please check your connection and try again.',
        });
      } finally {
        setLoading(false);
      }
    };

    void load();
  }, [isOpen, channel]);

  const handleSelect = async (template: Template) => {
    if (isSaving) return;
    setIsSaving(true);
    try {
      const spec = parseWorkflowYAML(template.code);
      const state = convertWorkflowSpecToState(spec);
      await importWorkflow(state);
      const saved = await saveWorkflow({ silent: true });
      if (!saved) {
        notifications.alert({
          title: 'Not connected',
          description: 'Connect to the server before creating a workflow.',
        });
        setIsSaving(false);
        return;
      }
      setIsSaving(false);
      closeTemplateBrowserModal();
      dismissLandingScreen();
    } catch {
      notifications.alert({
        title: 'Failed to create workflow',
        description: 'Please check your connection and try again.',
      });
      setIsSaving(false);
    }
  };

  return (
    <TemplateBrowserModal
      isOpen={isOpen}
      onClose={closeTemplateBrowserModal}
      templates={templates}
      loading={loading}
      isSaving={isSaving}
      onSelect={template => void handleSelect(template)}
      searchQuery={searchQuery}
      onSearchChange={setSearchQuery}
    />
  );
}
