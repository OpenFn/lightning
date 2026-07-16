import { useEffect } from 'react';

import { parseWorkflowYAML, convertWorkflowSpecToState } from '../../yaml/util';
import { fetchTemplates } from '../api/templates';
import { BASE_TEMPLATES } from '../constants/baseTemplates';
import { useActionLock } from '../hooks/useActionLock';
import { useSession } from '../hooks/useSession';
import {
  useShowTemplateBrowserModal,
  useTemplatePanel,
  useUICommands,
} from '../hooks/useUI';
import { useCreateWorkflowFlow } from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';
import { notifications } from '../lib/notifications';
import type { Template } from '../types/template';

import { TemplateBrowserModal } from './TemplateBrowserModal';

export function TemplateBrowserModalWrapper() {
  const isOpen = useShowTemplateBrowserModal();
  const {
    closeTemplateBrowserModal,
    dismissLandingScreen,
    setTemplates,
    setTemplatesLoading,
    setTemplateSearchQuery,
  } = useUICommands();
  const provider = useSession(s => s.provider);
  const channel = provider?.channel;
  const { createWorkflowFrom } = useCreateWorkflowFlow();

  const { templates, loading, searchQuery } = useTemplatePanel();

  useKeyboardShortcut('Escape', closeTemplateBrowserModal, 100, {
    enabled: isOpen,
  });

  // Lazy fetch — only when modal opens, not on every /new load
  useEffect(() => {
    if (!isOpen) return;
    setTemplateSearchQuery('');
    if (!channel) return;

    // Guards against a close-before-resolve-then-reopen race: without this,
    // a stale fetch from a previous open can resolve after a newer one and
    // overwrite its result.
    let cancelled = false;

    const load = async () => {
      setTemplatesLoading(true);
      try {
        const userTemplates = await fetchTemplates(channel);
        if (cancelled) return;
        setTemplates([...BASE_TEMPLATES, ...userTemplates]);
      } catch {
        if (cancelled) return;
        notifications.alert({
          title: 'Failed to load templates',
          description: 'Please check your connection and try again.',
        });
      } finally {
        if (!cancelled) setTemplatesLoading(false);
      }
    };

    void load();

    return () => {
      cancelled = true;
    };
  }, [
    isOpen,
    channel,
    setTemplateSearchQuery,
    setTemplatesLoading,
    setTemplates,
  ]);

  const { run: handleSelect, isPending: isSaving } = useActionLock(
    async (template: Template) => {
      const created = await createWorkflowFrom(() =>
        convertWorkflowSpecToState(parseWorkflowYAML(template.code))
      );
      if (created) {
        closeTemplateBrowserModal();
        dismissLandingScreen();
      }
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
      onSearchChange={setTemplateSearchQuery}
    />
  );
}
