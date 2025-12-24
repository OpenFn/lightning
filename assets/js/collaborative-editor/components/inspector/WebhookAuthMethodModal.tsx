import {
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
} from '@headlessui/react';
import { useState } from 'react';

import { cn } from '#/utils/cn';

import { useLiveViewActions } from '../../contexts/LiveViewActionsContext';
import type { WebhookAuthMethod } from '../../types/sessionContext';
import type { Workflow } from '../../types/workflow';

interface WebhookAuthMethodModalProps {
  trigger: Workflow.Trigger;
  projectAuthMethods: WebhookAuthMethod[];
  projectId: string;
  onClose: () => void;
  onSave: (selectedMethodIds: string[]) => Promise<void>;
}

export function WebhookAuthMethodModal({
  trigger,
  projectAuthMethods,
  projectId,
  onClose,
  onSave,
}: WebhookAuthMethodModalProps) {
  const [selections, setSelections] = useState<Record<string, boolean>>(() => {
    // Initialize with current trigger associations
    const initial: Record<string, boolean> = {};
    projectAuthMethods.forEach(method => {
      initial[method.id] =
        trigger.webhook_auth_methods?.some(m => m.id === method.id) ?? false;
    });
    return initial;
  });

  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { pushEvent } = useLiveViewActions();

  const handleToggle = (methodId: string) => {
    setSelections(prev => ({
      ...prev,
      [methodId]: !prev[methodId],
    }));
  };

  const handleSave = async () => {
    setIsSaving(true);
    setError(null);

    try {
      const selectedIds = Object.entries(selections)
        .filter(([_, selected]) => selected)
        .map(([id]) => id);

      await onSave(selectedIds);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save');
    } finally {
      setIsSaving(false);
    }
  };

  const selectedCount = Object.values(selections).filter(Boolean).length;

  return (
    <Dialog open={true} onClose={onClose} className="relative z-50">
      <DialogBackdrop
        transition
        className="fixed inset-0 bg-gray-900/60 backdrop-blur-sm transition-opacity
          data-closed:opacity-0 data-enter:duration-300
          data-enter:ease-out data-leave:duration-200 data-leave:ease-in"
      />

      <div className="fixed inset-0 z-10 w-screen overflow-y-auto">
        <div
          className="flex min-h-full items-end justify-center p-4
            text-center sm:items-center sm:p-0"
        >
          <DialogPanel
            transition
            className="relative transform overflow-hidden rounded-lg
              bg-white text-left shadow-xl transition-all
              data-closed:translate-y-4 data-closed:opacity-0
              data-enter:duration-300 data-enter:ease-out
              data-leave:duration-200 data-leave:ease-in
              sm:my-8 sm:w-full sm:max-w-lg"
          >
            {/* Header */}
            <div className="px-6 py-4 border-b border-gray-200">
              <div className="flex items-start justify-between">
                <div>
                  <DialogTitle
                    as="h3"
                    className="text-lg font-semibold text-gray-900"
                  >
                    Webhook Authentication Methods
                  </DialogTitle>
                  <p className="mt-1 text-sm text-gray-500">
                    Select which authentication methods apply to this webhook
                    trigger
                  </p>
                </div>
                <button
                  type="button"
                  onClick={onClose}
                  className="rounded-md text-gray-400 hover:text-gray-500
                    focus:outline-none"
                >
                  <span className="sr-only">Close</span>
                  <span className="hero-x-mark h-5 w-5" aria-hidden="true" />
                </button>
              </div>
            </div>

            {/* Body */}
            <div className="px-6 py-4">
              {error && (
                <div className="mb-4 rounded-md bg-red-50 p-3">
                  <p className="text-sm text-red-800">{error}</p>
                </div>
              )}

              {projectAuthMethods.length === 0 ? (
                <div className="py-8 text-center">
                  <span
                    className="hero-shield-exclamation h-12 w-12 mx-auto
                    text-gray-400 mb-3"
                    aria-hidden="true"
                  />
                  <p className="text-sm text-gray-600 mb-2">
                    No webhook authentication methods available.
                  </p>
                  <button
                    type="button"
                    onClick={() => {
                      onClose();
                      pushEvent('open_webhook_auth_modal', {});
                    }}
                    className="link text-sm"
                  >
                    Create a new authentication method
                  </button>
                </div>
              ) : (
                <div className="space-y-2">
                  {projectAuthMethods.map(method => (
                    <label
                      key={method.id}
                      className={cn(
                        'flex items-center gap-3 p-3 border rounded-lg',
                        'cursor-pointer transition-colors',
                        selections[method.id]
                          ? 'border-indigo-300 bg-indigo-50'
                          : 'border-gray-200 hover:bg-gray-50'
                      )}
                    >
                      <input
                        type="checkbox"
                        checked={selections[method.id] ?? false}
                        onChange={() => handleToggle(method.id)}
                        className="h-4 w-4 text-indigo-600 border-gray-300
                        rounded focus:ring-indigo-500"
                      />
                      <div className="flex-1 min-w-0">
                        <div
                          className="text-sm font-medium text-gray-900
                        truncate"
                        >
                          {method.name}
                        </div>
                        <div className="text-xs text-gray-500">
                          {method.auth_type === 'api'
                            ? 'API Key'
                            : 'Basic Authentication'}
                        </div>
                      </div>
                      {selections[method.id] && (
                        <span
                          className="hero-check-circle text-indigo-600 h-5
                          w-5 flex-shrink-0"
                        />
                      )}
                    </label>
                  ))}
                </div>
              )}

              {projectAuthMethods.length > 0 && (
                <div className="mt-4 pt-4 border-t border-gray-200">
                  <p className="text-xs text-gray-500">
                    <button
                      type="button"
                      onClick={() => {
                        onClose();
                        pushEvent('open_webhook_auth_modal', {});
                      }}
                      className="link"
                    >
                      Create a new authentication method
                    </button>
                    {' or manage them in '}
                    <a
                      href={`/projects/${projectId}/settings#webhook_security`}
                      className="link"
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      project settings
                    </a>
                  </p>
                </div>
              )}
            </div>

            {/* Footer */}
            <div
              className="border-t border-gray-200 px-6 py-4 flex
              justify-between items-center bg-gray-50"
            >
              <div className="text-sm text-gray-600">
                {selectedCount} {selectedCount === 1 ? 'method' : 'methods'}
                {' selected'}
              </div>
              <div className="flex gap-3">
                <button
                  type="button"
                  onClick={onClose}
                  disabled={isSaving}
                  className="px-4 py-2 text-sm font-medium text-gray-700
                  bg-white border border-gray-300 rounded-md
                  hover:bg-gray-50 focus:outline-none focus:ring-2
                  focus:ring-offset-2 focus:ring-indigo-500
                  disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  onClick={() => {
                    void handleSave();
                  }}
                  disabled={isSaving || projectAuthMethods.length === 0}
                  className="px-4 py-2 text-sm font-medium text-white
                  bg-indigo-600 rounded-md hover:bg-indigo-700
                  focus:outline-none focus:ring-2 focus:ring-offset-2
                  focus:ring-indigo-500 disabled:opacity-50
                  disabled:cursor-not-allowed"
                >
                  {isSaving ? 'Saving...' : 'Save'}
                </button>
              </div>
            </div>
          </DialogPanel>
        </div>
      </div>
    </Dialog>
  );
}
