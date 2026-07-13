import { useEffect, useState } from 'react';

import { parseWorkflowYAML, convertWorkflowSpecToState } from '../../yaml/util';
import { fetchTemplates } from '../api/templates';
import { BASE_TEMPLATES } from '../constants/baseTemplates';
import { useActionLock } from '../hooks/useActionLock';
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
  const provider = useSession(s => s.provider);
  const isConnected = useSession(s => s.isConnected);
  const channel = provider?.channel;
  const { importWorkflow, saveWorkflow } = useWorkflowActions();

  const [templates, setTemplates] = useState<Template[]>(BASE_TEMPLATES);
  const [loading, setLoading] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');

  useKeyboardShortcut('Escape', closeTemplateBrowserModal, 100, {
    enabled: isOpen,
  });

  // Lazy fetch — only when modal opens, not on every /new load
  useEffect(() => {
    if (!isOpen) return;
    setSearchQuery('');
    if (!channel) return;

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

  const { run: handleSelect, isPending: isSaving } = useActionLock(
    async (template: Template) => {
      if (!isConnected) {
        notifications.alert({
          title: 'Not connected',
          description: 'Connection lost — please wait a moment and try again.',
        });
        return;
      }
      try {
        const spec = parseWorkflowYAML(template.code);
        const state = convertWorkflowSpecToState(spec);
        await importWorkflow(state);
      } catch {
        notifications.alert({
          title: 'Failed to create workflow',
          description: 'Please check your connection and try again.',
        });
        return;
      }
      try {
        await saveWorkflow({ notify: 'error-only' });
      } catch {
        // Shared handler has shown a persistent Retry toast; a successful
        // retry patches the URL and unmounts this modal via the
        // isNewWorkflow gate.
        return;
      }
      closeTemplateBrowserModal();
      dismissLandingScreen();
    }
  );

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
