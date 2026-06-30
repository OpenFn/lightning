import { Dialog, DialogBackdrop, DialogPanel } from '@headlessui/react';
import { useEffect, useState } from 'react';

import { cn } from '#/utils/cn';

import { parseWorkflowYAML, convertWorkflowSpecToState } from '../../yaml/util';
import { fetchTemplates } from '../api/templates';
import { BASE_TEMPLATES } from '../constants/baseTemplates';
import { useSession } from '../hooks/useSession';
import { useShowTemplateBrowserModal, useUICommands } from '../hooks/useUI';
import { useWorkflowActions } from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';
import { notifications } from '../lib/notifications';
import type { Template } from '../types/template';

export function WorkflowTemplateBrowserModal() {
  const isOpen = useShowTemplateBrowserModal();
  const { closeTemplateBrowserModal, dismissLandingScreen } = useUICommands();
  const { provider } = useSession();
  const channel = provider?.channel;
  const { importWorkflow, saveWorkflow } = useWorkflowActions();

  const [templates, setTemplates] = useState<Template[]>([]);
  const [loading, setLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);

  let cols = 1;
  if (templates.length > 6) cols = 3;
  else if (templates.length > 3) cols = 2;

  useKeyboardShortcut('Escape', closeTemplateBrowserModal, 100, {
    enabled: isOpen,
  });

  // Lazy fetch — only when modal opens, not on every /new load
  useEffect(() => {
    if (!isOpen || !channel) return;

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
    <Dialog
      open={isOpen}
      onClose={closeTemplateBrowserModal}
      className="relative z-20"
      aria-label="Browse workflow templates"
    >
      <DialogBackdrop
        transition
        className="modal-backdrop data-closed:opacity-0 data-enter:duration-300
          data-enter:ease-out data-leave:duration-200 data-leave:ease-in"
      />
      <div className="fixed inset-0 z-10 flex items-center justify-center p-4">
        <DialogPanel
          transition
          className={cn(
            'bg-white rounded-2xl shadow-2xl w-full flex flex-col',
            'data-closed:opacity-0 data-closed:scale-95',
            'data-enter:duration-300 data-enter:ease-out',
            'data-leave:duration-200 data-leave:ease-in',
            {
              'max-w-lg': cols === 1,
              'max-w-2xl': cols === 2,
              'max-w-[784px]': cols === 3,
            }
          )}
        >
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-5">
            <h2 className="text-xl text-gray-900">Templates</h2>
            <button
              type="button"
              onClick={closeTemplateBrowserModal}
              className="rounded-md p-1 text-gray-400 hover:text-gray-600 hover:bg-gray-100 transition-colors"
              aria-label="Close"
            >
              <span className="hero-x-mark h-5 w-5" />
            </button>
          </div>

          {/* Content */}
          <div className="px-6 pb-5 overflow-y-auto max-h-96">
            {loading ? (
              <p className="text-sm text-gray-500 text-center py-8">
                Loading templates...
              </p>
            ) : (
              <div
                className={cn('grid gap-4', {
                  'grid-cols-1': cols === 1,
                  'grid-cols-2': cols === 2,
                  'grid-cols-3': cols === 3,
                })}
              >
                {templates.map(template => (
                  <TemplateSelectCard
                    key={template.id}
                    template={template}
                    disabled={isSaving}
                    onClick={() => void handleSelect(template)}
                  />
                ))}
              </div>
            )}
          </div>
        </DialogPanel>
      </div>
    </Dialog>
  );
}

interface TemplateSelectCardProps {
  template: Template;
  disabled: boolean;
  onClick: () => void;
}

function TemplateSelectCard({
  template,
  disabled,
  onClick,
}: TemplateSelectCardProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="w-full h-full text-left rounded-lg border border-gray-200 bg-white p-3
        hover:border-gray-300 hover:bg-gray-50 transition-colors
        disabled:opacity-50 disabled:cursor-not-allowed
        focus:outline-none focus-visible:ring focus-visible:ring-gray-300"
    >
      <p className="text-sm font-medium text-gray-900">{template.name}</p>
      {template.description && (
        <p className="mt-0.5 text-sm text-gray-500 line-clamp-2">
          {template.description}
        </p>
      )}
    </button>
  );
}
