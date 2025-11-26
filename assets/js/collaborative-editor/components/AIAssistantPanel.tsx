import { useEffect, useState, useSyncExternalStore } from 'react';

import { cn } from '#/utils/cn';

import type { AIAssistantStore } from '../types/ai-assistant';

import { ChatInput } from './ChatInput';
import { SessionList } from './SessionList';

interface AIAssistantPanelProps {
  isOpen: boolean;
  onClose: () => void;
  onNewConversation?: () => void;
  onSessionSelect?: (sessionId: string) => void;
  onShowSessions?: () => void;
  onSendMessage?: (content: string, options?: MessageOptions) => void;
  children?: React.ReactNode;
  sessionId?: string | null;
  messageCount?: number;
  isLoading?: boolean;
  /**
   * Whether this panel is inside a resizable Panel component (IDE mode)
   * or standalone with fixed width (Canvas mode)
   */
  isResizable?: boolean;
  /**
   * AI Assistant store for session list
   */
  store?: AIAssistantStore;
  /**
   * Current session type (job_code or workflow_template)
   * Used to show mode-specific UI
   */
  sessionType?: 'job_code' | 'workflow_template' | null;
  /**
   * Load sessions via Phoenix Channel (preferred over HTTP)
   */
  loadSessions?: (offset?: number, limit?: number) => Promise<void>;
}

interface MessageOptions {
  attach_code?: boolean;
  attach_logs?: boolean;
}

/**
 * AI Assistant Panel Component
 *
 * Full-height right-side panel similar to Google Cloud Assistant.
 * Pushes content to the left when open (not an overlay).
 *
 * Design Specifications:
 * - Positioned on the right side, pushes content left when open
 * - Full viewport height
 * - Resizable in IDE mode, fixed 400px width in Canvas mode
 * - Smooth slide-in/out transitions
 * - No backdrop overlay (content pushes instead of overlaying)
 * - Escape key to close
 */
export function AIAssistantPanel({
  isOpen,
  onClose,
  onNewConversation: _onNewConversation,
  onSessionSelect,
  onShowSessions,
  onSendMessage,
  children,
  sessionId,
  messageCount: _messageCount = 0,
  isLoading = false,
  isResizable = false,
  store,
  sessionType = null,
  loadSessions,
}: AIAssistantPanelProps) {
  // Start with sessions list if no active session
  const [view, setView] = useState<'chat' | 'sessions'>(
    sessionId ? 'chat' : 'sessions'
  );
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [isAboutOpen, setIsAboutOpen] = useState(false);

  // Subscribe to store context changes to compute storage key reactively
  const storageKey: string | undefined = useSyncExternalStore(
    store?.subscribe ?? (() => () => {}),
    () => {
      if (!store) {
        console.log('[AIAssistantPanel] No store available for storageKey');
        return undefined;
      }
      const state = store.getSnapshot();
      if (state.sessionType === 'job_code' && state.jobCodeContext?.job_id) {
        const key = `ai-job-${state.jobCodeContext.job_id}`;
        console.log('[AIAssistantPanel] Computed storageKey:', key);
        return key;
      }
      if (state.sessionType === 'workflow_template') {
        if (state.workflowTemplateContext?.workflow_id) {
          const key = `ai-workflow-${state.workflowTemplateContext.workflow_id}`;
          console.log('[AIAssistantPanel] Computed storageKey:', key);
          return key;
        }
        if (state.workflowTemplateContext?.project_id) {
          const key = `ai-project-${state.workflowTemplateContext.project_id}`;
          console.log('[AIAssistantPanel] Computed storageKey:', key);
          return key;
        }
      }
      console.log('[AIAssistantPanel] No valid context for storageKey', {
        sessionType: state.sessionType,
        hasJobContext: !!state.jobCodeContext,
        hasWorkflowContext: !!state.workflowTemplateContext,
      });
      return undefined;
    }
  );

  // Switch view based on sessionId changes
  useEffect(() => {
    if (sessionId && view === 'sessions') {
      // Session created/loaded -> show chat
      setView('chat');
    } else if (!sessionId && view === 'chat') {
      // Session cleared -> show sessions list
      setView('sessions');
    }
  }, [sessionId, view]);

  // Handle escape key to close panel
  useEffect(() => {
    const handleEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && isOpen) {
        onClose();
      }
    };

    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [isOpen, onClose]);

  // Subscribe to store context to detect when it's initialized
  const storeSessionType = useSyncExternalStore(
    store?.subscribe ?? (() => () => {}),
    () => store?.getSnapshot().sessionType ?? null
  );

  // Load session list when view is 'sessions' AND context is ready
  useEffect(() => {
    if (view !== 'sessions' || !store || !storeSessionType) return;

    // Double-check context is actually set
    const state = store.getSnapshot();
    const hasContext = !!(
      state.jobCodeContext || state.workflowTemplateContext
    );

    if (!hasContext) {
      console.warn('[AIAssistantPanel] Context not ready yet', {
        sessionType: storeSessionType,
        hasJobContext: !!state.jobCodeContext,
        hasWorkflowContext: !!state.workflowTemplateContext,
      });
      return;
    }

    console.log(
      '[AIAssistantPanel] Loading sessions for mode:',
      storeSessionType
    );

    // Prefer Phoenix Channel when available, fallback to HTTP
    if (loadSessions) {
      void loadSessions().catch(error => {
        console.warn(
          '[AIAssistantPanel] Channel load failed, using HTTP:',
          error
        );
        void store.loadSessionList();
      });
    } else {
      void store.loadSessionList();
    }
  }, [view, store, storeSessionType, loadSessions]);

  const handleShowSessions = () => {
    // Set view to sessions without clearing session
    // This keeps the connection alive for fetching sessions
    setView('sessions');
    setIsMenuOpen(false);

    // Clear URL params only (don't disconnect)
    if (onShowSessions) {
      onShowSessions();
    }
  };

  const handleToggleMenu = () => {
    setIsMenuOpen(prev => !prev);
  };

  const handleOpenAbout = () => {
    setIsAboutOpen(true);
    setIsMenuOpen(false);
  };

  const handleSessionSelect = (selectedSessionId: string) => {
    if (onSessionSelect) {
      onSessionSelect(selectedSessionId);
      setView('chat');
    }
  };

  const handleClose = () => {
    if (sessionId) {
      // If viewing a session, close it and return to sessions list
      // View will automatically switch to 'sessions' via the effect when sessionId becomes null
      if (onShowSessions) {
        onShowSessions();
      }
    } else {
      // If in sessions list (no session), close entire panel
      onClose();
    }
  };

  // Close menu when clicking outside
  useEffect(() => {
    if (!isMenuOpen) return;

    const handleClickOutside = (event: MouseEvent) => {
      const target = event.target as HTMLElement;
      if (
        !target.closest('[data-menu-trigger]') &&
        !target.closest('[data-menu-content]')
      ) {
        setIsMenuOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [isMenuOpen]);

  return (
    <div
      className={cn(
        'h-full flex flex-col overflow-hidden bg-white',
        !isResizable && [
          'flex-none border-l border-gray-200',
          'transition-all duration-300 ease-in-out',
          isOpen ? 'w-[400px]' : 'w-0 border-l-0',
        ]
      )}
      role="dialog"
      aria-modal="false"
      aria-label="AI Assistant"
    >
      {/* Panel Header */}
      <div className="flex-none bg-white shadow-xs border-b border-gray-200">
        <div className="mx-auto px-6 py-6 flex items-center justify-between h-20 text-sm">
          <div className="flex items-center gap-2 min-w-0 flex-1">
            <img src="/images/logo.svg" alt="OpenFn" className="size-6" />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <h2 className="text-base font-semibold text-gray-900">
                  Assistant
                </h2>
                {/* Mode indicator badge */}
                {sessionType && (
                  <span
                    className={cn(
                      'inline-flex items-center px-2 py-0.5 rounded text-xs font-medium',
                      sessionType === 'job_code'
                        ? 'bg-blue-100 text-blue-800'
                        : 'bg-purple-100 text-purple-800'
                    )}
                  >
                    {sessionType === 'job_code' ? 'Job' : 'Workflow'}
                  </span>
                )}
              </div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {/* 3-dot vertical menu */}
            {store && (
              <div className="relative">
                <button
                  type="button"
                  onClick={handleToggleMenu}
                  data-menu-trigger
                  className={cn(
                    'inline-flex items-center justify-center',
                    'h-8 w-8 rounded-md',
                    'text-gray-500 hover:text-gray-700 hover:bg-gray-100',
                    'focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500',
                    'transition-all duration-150',
                    isMenuOpen && 'bg-gray-100 text-gray-700'
                  )}
                  aria-label="More options"
                  aria-expanded={isMenuOpen}
                >
                  <span className="hero-ellipsis-vertical h-5 w-5" />
                </button>
                {/* Dropdown Menu */}
                {isMenuOpen && (
                  <div
                    data-menu-content
                    className={cn(
                      'absolute right-0 mt-2 w-64 origin-top-right',
                      'rounded-lg shadow-xl',
                      'bg-white ring-1 ring-gray-900/10',
                      'divide-y divide-gray-100',
                      'z-50',
                      'animate-in fade-in-0 zoom-in-95 duration-100'
                    )}
                  >
                    <div className="py-1.5">
                      <button
                        type="button"
                        onClick={handleShowSessions}
                        className={cn(
                          'group flex items-center w-full',
                          'px-4 py-2.5 text-sm font-medium',
                          'text-gray-700 hover:bg-gray-50',
                          'transition-colors duration-150',
                          view === 'sessions' &&
                            'bg-primary-50 text-primary-700'
                        )}
                      >
                        <span
                          className={cn(
                            'hero-chat-bubble-left-right h-5 w-5 mr-3',
                            view === 'sessions'
                              ? 'text-primary-600'
                              : 'text-gray-400 group-hover:text-gray-500'
                          )}
                        />
                        <span className="flex-1 text-left">Chat History</span>
                        {view === 'sessions' && (
                          <span className="hero-check h-4 w-4 text-primary-600 ml-2" />
                        )}
                      </button>
                    </div>
                    <div className="py-1.5">
                      <button
                        type="button"
                        onClick={handleOpenAbout}
                        className={cn(
                          'group flex items-center w-full',
                          'px-4 py-2.5 text-sm',
                          'text-gray-700 hover:bg-gray-50',
                          'transition-colors duration-150'
                        )}
                      >
                        <span className="hero-information-circle h-5 w-5 mr-3 text-gray-400 group-hover:text-gray-500" />
                        <span>About the AI Assistant</span>
                      </button>
                      <a
                        href="https://www.openfn.org/ai"
                        target="_blank"
                        rel="noopener noreferrer"
                        className={cn(
                          'group flex items-center w-full',
                          'px-4 py-2.5 text-sm',
                          'text-gray-700 hover:bg-gray-50',
                          'transition-colors duration-150'
                        )}
                      >
                        <span className="hero-document-text h-5 w-5 mr-3 text-gray-400 group-hover:text-gray-500" />
                        <span className="flex-1">
                          OpenFn Responsible AI Policy
                        </span>
                        <span className="hero-arrow-top-right-on-square h-4 w-4 ml-2 text-gray-400 group-hover:text-gray-500" />
                      </a>
                    </div>
                  </div>
                )}
              </div>
            )}
            <button
              type="button"
              onClick={handleClose}
              className={cn(
                'inline-flex items-center justify-center',
                'h-8 w-8 rounded-md',
                'text-gray-400 hover:text-gray-600 hover:bg-gray-100',
                'focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500',
                'transition-all duration-150',
                'flex-shrink-0'
              )}
              aria-label={
                sessionId
                  ? 'Close session and return to sessions list'
                  : 'Close AI Assistant'
              }
            >
              <span className="hero-x-mark h-5 w-5" />
            </button>
          </div>
        </div>
      </div>

      {/* Panel Content - Messages or Sessions */}
      <div className="flex-1 overflow-hidden bg-white">
        {view === 'chat' ? (
          <div className="h-full overflow-y-auto">{children}</div>
        ) : (
          store && (
            <SessionList
              store={store}
              onSessionSelect={handleSessionSelect}
              currentSessionId={sessionId}
            />
          )
        )}
      </div>

      {/* Chat Input - Always visible at bottom */}
      <ChatInput
        onSendMessage={onSendMessage}
        isLoading={isLoading}
        showJobControls={sessionType === 'job_code'}
        storageKey={storageKey}
      />

      {/* About AI Assistant Modal */}
      {isAboutOpen && (
        <div className="absolute inset-0 z-50 bg-white flex flex-col">
          {/* Modal Header */}
          <div className="flex-none bg-gray-50 px-4 py-3 flex items-center justify-between border-b border-gray-200">
            <h3 className="font-medium text-gray-900">
              About the AI Assistant
            </h3>
            <button
              type="button"
              onClick={() => setIsAboutOpen(false)}
              className={cn(
                'rounded-md text-gray-400 hover:text-gray-600',
                'hover:bg-gray-100 transition-colors',
                'focus:outline-none focus:ring-2 focus:ring-primary-500',
                'p-1'
              )}
              aria-label="Close"
            >
              <span className="hero-x-mark h-5 w-5" />
            </button>
          </div>

          {/* Modal Content */}
          <div className="flex-1 overflow-y-auto p-4 text-sm space-y-4">
            <p>
              The OpenFn AI Assistant provides a chat interface with an AI Model
              to help you build workflows. It can:
            </p>
            <ul className="list-disc list-inside pl-4 space-y-1">
              <li>Create a workflow template for you</li>
              <li>Draft job code for you</li>
              <li>Explain adaptor functions and how they are used</li>
              <li>Proofread and debug your job code</li>
              <li>Help understand why you are seeing an error</li>
            </ul>
            <p>
              Messages are saved unencrypted to the OpenFn database and may be
              monitored for quality control.
            </p>

            <h4 className="font-semibold text-gray-900 pt-2">Usage Tips</h4>
            <ul className="list-disc list-inside pl-4 space-y-1">
              <li>
                All chats are saved to the Project and can be viewed at any time
              </li>
              <li>
                Press{' '}
                <code className="px-1 py-0.5 bg-gray-100 rounded text-xs">
                  CTRL + ENTER
                </code>{' '}
                to send a message
              </li>
              <li>
                The Assistant can see your code and knows about OpenFn - just
                ask a question and don't worry too much about giving it context
              </li>
            </ul>

            <h4 className="font-semibold text-gray-900 pt-2">
              Using The Assistant Safely
            </h4>
            <p>
              The AI assistant uses a third-party model to process chat
              messages. Messages may be saved on OpenFn and Anthropic servers.
            </p>
            <p>
              Although we are constantly monitoring and improving the
              performance of the model, the Assistant can sometimes provide
              incorrect or misleading responses. You should consider the
              responses critically and verify the output where possible.
            </p>
            <p>
              Remember that all responses are generated by an algorithm, and you
              are responsible for how its output is used.
            </p>
            <p>
              Do not deploy autogenerated code in production environments
              without thorough testing.
            </p>
            <p>
              Do not include real user data, personally identifiable
              information, or sensitive business data in your queries.
            </p>

            <h4 className="font-semibold text-gray-900 pt-2">How it works</h4>
            <p>
              The Assistant uses Claude Sonnet 3.7, by{' '}
              <a
                href="https://www.anthropic.com/"
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-600 hover:text-primary-700"
              >
                Anthropic
              </a>
              , a Large Language Model (LLM) designed with a commitment to
              safety and privacy.
            </p>
            <p>
              Chat is saved with the Step and shared with all users with access
              to the Workflow. All collaborators within a project can see
              questions asked by other users.
            </p>
            <p>
              We include your step code in all queries sent to Claude, including
              some basic documentation, ensuring the model is well informed and
              can see what you can see. We do not send your input data, output
              data or logs to Anthropic.
            </p>
            <p>
              The Assistant uses a mixture of hand-written prompts and
              information from{' '}
              <a
                href="https://docs.openfn.org"
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-600 hover:text-primary-700"
              >
                docs.openfn.org
              </a>{' '}
              to inform its responses.
            </p>

            <h4 className="font-semibold text-gray-900 pt-2">
              Responsible AI Policy
            </h4>
            <p>
              Read about our approach to AI in the{' '}
              <a
                href="https://www.openfn.org/ai"
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-600 hover:text-primary-700"
              >
                OpenFn Responsible AI Policy
              </a>
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
